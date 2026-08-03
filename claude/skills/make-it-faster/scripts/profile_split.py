"""Split a cProfile run into extraction time vs compute time.

Works because CPython's profiler times on `PyTime_PerfCounterRaw` — wall clock, which
includes time blocked — so `cumtime` on a driver call IS the database/network wait, and
C methods are labelled `{method 'execute' of 'pyodbc.Cursor' objects}` by pstats.

Attribution rule: a frame counts as extraction if it lives inside a driver/HTTP package
(path-segment match, so `snowflake/connector/network.py` matches but a user file named
`execute_report.py` does not), and its cumtime is credited only where an UNMATCHED
caller enters the matched subtree — taken from the pstats caller graph. Summing every
matched frame's cumtime would count a depth-d driver call chain d times.

Two hard caveats this script prints rather than hides:

- cProfile sees the MAIN THREAD ONLY (`sys.setprofile` is per-thread). A
  ThreadPoolExecutor extraction is invisible; cross-check with `py-spy --idle`.
- Overhead scales with Python-level call count, inflating the compute side. On a
  C-dominated workload (driver fetch + Polars + NumPy) it is small, but a very large
  total ncalls means the ratio should not be trusted.

Usage:
    python profile_split.py run.prof [top_n]
"""

import pstats
import sys

# Path segments identifying extraction packages (drivers + HTTP + stdlib sockets).
PKG_SEGMENTS = {
    "pyodbc",
    "snowflake",
    "clickhouse_connect",
    "clickhouse_driver",
    "arrow_odbc",
    "adbc_driver_manager",
    "adbc_driver_snowflake",
    "requests",
    "urllib3",
    "httpx",
    "httpcore",
    "aiohttp",
    "socket",
    "ssl",
    "http",
}

# Substrings identifying an extraction call in a C-frame label (filename == "~"),
# e.g. "{method 'execute' of 'pyodbc.Cursor' objects}".
C_LABEL_HINTS = (
    "pyodbc",
    "snowflake",
    "clickhouse",
    "_socket",
    "'ssl",
    "execute",
    "fetch",
)

# Callee names whose entry count from user code is the N+1 round-trip signal.
QUERY_NAMES = {
    "execute",
    "executemany",
    "query",
    "query_arrow",
    "query_df_arrow",
    "read_database",
    "urlopen",
    "request",
    "send",
    "get",
    "post",
}


def _is_extraction(func: tuple[str, int, str]) -> bool:
    filename, _lineno, name = func
    if filename == "~":
        return any(h in name for h in C_LABEL_HINTS)
    if "/polars/io/" in filename.replace("\\", "/"):
        return True
    parts = filename.replace("\\", "/").split("/")
    segments = {p.removesuffix(".py") for p in parts if p}
    return not segments.isdisjoint(PKG_SEGMENTS)


def split(path: str, top_n: int = 25) -> None:
    """Print the extraction/compute split and the N+1 signal for a .prof file.

    Args:
        path: Path to a cProfile output file.
        top_n: How many extraction rows to list.
    """
    stats = pstats.Stats(path)
    total_wall = max(
        (ct for _cc, _nc, _tt, ct, _cal in stats.stats.values()), default=0.0
    )

    matched = {f for f in stats.stats if _is_extraction(f)}

    rows = []
    py_calls = 0
    query_calls = 0
    for func, (_cc, nc, _tt, ct, callers) in stats.stats.items():
        filename, lineno, name = func
        is_c = filename == "~"
        if not is_c:
            py_calls += nc
        if func not in matched:
            continue
        # Credit cumtime (and query calls) only at the boundary where unmatched
        # code enters the matched subtree; a root entry has no callers.
        if callers:
            entry_ct = sum(c[3] for f, c in callers.items() if f not in matched)
            entry_nc = sum(c[1] for f, c in callers.items() if f not in matched)
        else:
            entry_ct, entry_nc = ct, nc
        if entry_ct > 0 or entry_nc > 0:
            label = name if is_c else f"{filename}:{lineno}({name})"
            rows.append((entry_ct, entry_nc, label))
        # fetch* counts toward extraction time but not round trips — a query already
        # counted at execute would otherwise be counted again at its fetch.
        if entry_nc and (name in QUERY_NAMES or (is_c and "execute" in name)):
            query_calls += entry_nc

    rows.sort(reverse=True)
    io_time = sum(t for t, _, _ in rows)
    compute = max(0.0, total_wall - io_time)

    print(f"{'seconds':>9} {'ncalls':>9}  where")
    for t, nc, label in rows[:top_n]:
        print(f"{t:>9.3f} {nc:>9}  {label}")

    print()
    print(f"total wall      : {total_wall:.3f}s")
    if total_wall:
        print(f"extraction      : {io_time:.3f}s  ({io_time / total_wall:.1%})")
        print(f"compute (approx): {compute:.3f}s  ({compute / total_wall:.1%})")
    print(f"query/request calls: {query_calls}")
    if query_calls > 50:
        print(
            f"SIGNAL: {query_calls} round trips — check for a per-row query inside a loop (N+1)."
        )
    if py_calls > 5_000_000:
        print(
            f"CAVEAT: {py_calls} Python-level calls — profiler overhead inflates the compute "
            "side here. Cross-check the split with py-spy --idle before trusting it."
        )
    print(
        "CAVEAT: cProfile measures the MAIN THREAD ONLY. If extraction is threaded, this "
        "undercounts it — confirm with py-spy --idle --threads."
    )


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: python profile_split.py run.prof [top_n]")
    split(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 25)
