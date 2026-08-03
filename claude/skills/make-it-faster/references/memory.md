# Memory: diagnosis, out-of-core, and the dev loop

## Which number predicts an OOM

**Peak RSS.** The OOM killer acts on resident pages and cgroup `memory.current`; nothing else.

- **Peak RSS** — `ru_maxrss` / `VmHWM` / cgroup `memory.peak`. Predicts OOM. No attribution.
- **High watermark of live allocations** — memray `metadata.peak_memory`, tracemalloc peak.
  Attributes, but only what the tool can see.
- **Total bytes allocated** — memray `total_bytes_allocated`. Predicts **nothing**; it sums
  transients over the whole run. Never report it as "memory used".

**`ru_maxrss` survives a SIGKILL — verified.** A child allocating 300 MB then killed with `-9`
still reported `ru_maxrss = 310.1 MB` to the parent. So **an OOM kill is a data point, not a lost
run**. Exit code 137 = 128+9 (SIGKILL — almost always the OOM killer, but any `kill -9` too;
confirm via `journalctl -k` / cgroup `memory.events` `oom_kill` before reporting it as OOM).
There is no traceback and no `finally`, so if you need per-stage attribution, log peak RSS and
batch index every batch.

**`ru_maxrss` is a whole-process lifetime high-water mark — it never goes down.** You cannot
verify a `del`/scoping fix within one run with it; it only shows the fix in a *two-run*
before/after comparison (or by sampling current RSS inside the run).

`/usr/bin/time -v` is **not installed on Arch** — `scripts/runstat.py` replaces it. `ru_maxrss`
is **KiB on Linux** (reportedly bytes on macOS — unverified).

## Why memray under-delivers here

**Polars statically links jemalloc as its Rust global allocator**
(`#[global_allocator]` wrapping `tikv_jemallocator::Jemalloc`), so memray cannot interpose.
memray's maintainer on the still-open #577: *"if someone would compile mimalloc statically, the
symbols won't be exposed and there is no way for us to properly override them."* Arrow's
maintainer describes the symptom: *"allocations which are logically malloc-like are reported as
mmap calls with very large allocation sizes."*

**Measured on a 4M-row Polars + NumPy group-by:** true peak RSS **208.5 MB**, memray
`metadata.peak_memory` **259.2 MB** — off by ~24%, and *over*-reporting rather than under. Either
way the absolute number is not a trustworthy OOM predictor for a Polars program.

**Two corrections to common assumptions:** tracemalloc is **not** blind to NumPy (NumPy's
allocator calls `PyTraceMalloc_Track`, and CPython counts all domains) — it is blind only to
Polars and Arrow C++. And `ulimit -m`/RLIMIT_RSS *"has effect only in Linux 2.4.x"* — dead.

**Ranked approach:** (1) `getrusage(RUSAGE_CHILDREN)` wrapper, always; (2) `systemd-run --user
--scope -p MemoryMax=4G -p MemorySwapMax=0` for containment, with the wrapper *inside* the scope;
(3) `memray run --native` → `stats --json` for attribution — **never `--aggregate`**, which
disables the stats reporter *and* writes nothing at all on an OOM kill. In the **default** format
the `.bin` is written incrementally, so it **survives the OOM kill** — feed the partial capture
to `memray stats` afterward instead of discarding the run; (4) in-process gauges.

`MemorySwapMax=0` alongside `MemoryMax=` converts a slow machine-wrecking swap-thrash into a
fast, deterministic, in-cgroup OOM kill. **Don't read the transient scope's `memory.peak`** — the
cgroup is gone by the time you `cat` it; take the number from the wrapper.

`RLIMIT_AS` (`ulimit -v`) is a poor proxy — it caps *address space*, which jemalloc over-reserves,
and it kills you for mmap'ing a file (the thing you did right). Its one legitimate use is
converting a SIGKILL into a catchable `MemoryError` traceback.

**In-process gauges:** `pa.default_memory_pool().max_memory()` (exact for Arrow C++, but does
**not** cover Polars, which has its own Rust Arrow); `df.estimated_size()` (see the String
under-report in `compute.md`; for Object dtype it reports **only the pointer size** — *"a huge
underestimation"* — so an Object column is effectively invisible to it). The divergence is itself
a diagnostic: if `sum(estimated_size of all live frames) << peak RSS`, the excess is either a
transient compute buffer or a *sliced* frame still pinning its full parent buffer.

## Why these programs blow up

Python object overhead is the multiplier. A CPython `int` is 28 bytes (16 head + 8 tag + 4 digit)
vs 4 bytes for an Arrow int32 slot, plus 8 bytes of list pointer — **~8.5×**. A `str` carries
~40 bytes of header before the first character. PEP 412 key-sharing claws back 10–20% only for
*object-oriented* programs, so it does **not** apply to `json.loads` dicts.

pymalloc arenas are 1 MiB and only return to the OS when fully empty — this is why RSS doesn't
drop after `del rows`.

**The four shapes:** holding the raw result plus a derived copy simultaneously · fetch buffer +
DataFrame at once (Snowflake's `client_prefetch_threads`: *"Increasing the value improves fetch
performance but requires more memory"*) · `fetchall()` (*"should not be used if there are a lot of
rows"*) · an eager `collect()` materialising everything.

## Streaming extraction, per source

- **Snowflake:** `fetch_arrow_batches()` yields `pa.Table` (**not** `RecordBatch`). Pass
  `force_microsecond_precision=True` before concatenating or batches can disagree on timestamp unit.
- **ClickHouse:** *"ClickHouse Connect only loads a single block at a time."* Use
  `query_arrow_stream` (yields `RecordBatch`), not the `*_row_*` variants. `with` is mandatory.
- **MSSQL:** `arrow-odbc` — *"Read the data of an ODBC data source as sequence of Apache Arrow
  record batches."* Polars auto-routes ODBC connection strings to it.
- **The gotcha that silently defeats batching:** `pl.read_database(..., iter_batches=True)` needs
  `stream_results=True` on the connection, or *"some drivers (such as psycopg2) will still
  materialise the entire result set client-side before batching the result locally."* Snowflake
  ignores `batch_size` entirely.

**Reduce as you stream** — fold each batch to its aggregate and `del` the rows. Safe for sum,
count, min, max, and (sum,count)→mean. **Not** safe for median, quantile, or exact distinct —
those need the sink path.

## Zero-copy traps

- **`pl.from_arrow(..., rechunk=True)` is the DEFAULT — that is a full copy.** Pass
  `rechunk=False` when streaming batches.
- PyArrow polarity is inconsistent: `Array.to_numpy` defaults `zero_copy_only=True` (raises);
  `Table.to_pandas` defaults `False` (silently copies).
- A slice has small `Table.nbytes` but full `get_total_buffer_size()` — the "I sliced it but RSS
  didn't drop" symptom.
- `itertools.chain([first], batches)` is lazy; `[first] + list(batches)` drains the whole stream
  first and doubles peak memory.

## Spilling and mmap

**Parquet cannot be memory-mapped** — *"Because Parquet data needs to be decoded from the Parquet
format and compression, it can't be directly mapped from disk."* So: **Parquet for the *cache*,
uncompressed Arrow IPC for *mmap*.** `pl.read_ipc(memory_map=True)` defaults to `False`, only
works uncompressed, and *"invalid arrow data is UB!"* — and you cannot rewrite the same filename.

**The honest mmap answer:** touched pages still count in RSS. What mmap does is convert
*unreclaimable anonymous* memory into *reclaimable file-backed* memory that the kernel can drop
*"without any write back cost when under pressure"*. Your RSS may not fall much; your risk of
being killed falls a lot. It does **nothing** if you scan every page. Measure `RssAnon` vs
`RssFile`, not the total.

**`del` vs scoping.** glibc serves allocations ≥ `M_MMAP_THRESHOLD` (128 KiB) via mmap, which
*"can always be independently released back to the system"* — so `del df` on a multi-GB Polars
frame genuinely drops RSS. A million small Python objects do **not** (one survivor pins a 1 MiB
arena). **Scoping beats `del`:** put the extraction in a function so the raw frame dies at return.

**Streaming's silent fallback** is the #1 cause of "I enabled streaming and it still OOM'd":
*"Some operations are inherently non-streaming… Polars will fall back to the in-memory engine."*
Verify with `show_graph(engine="streaming", plan_stage="physical")` and `POLARS_VERBOSE=1`.

Known open regression: #28312 — `scan_parquet → sink_parquet` memory regression in 1.42.0
(~8 GB → ~15 GB); workaround `POLARS_ROW_GROUP_PREFETCH_SIZE=64`. When streaming still OOMs, the
levers in order are: smaller row groups → `POLARS_MAX_THREADS` down →
`POLARS_ROW_GROUP_PREFETCH_SIZE` down → `sink_*` instead of `collect` → pin the Polars version.

## Caching the extract for the dev loop

**`joblib.Memory` is NOT the answer** — this reversed on evidence. Its own docs: cross-session
identity is *"the function's name"*, and hashes are *"not guaranteed to stay constant across
`joblib` versions"*. Fatally — documented by tpcp's caching guide, **not** loudly by joblib
itself: *"joblib can not store dependencies of the function. This means, if your function calls
other functions, they will not be stored in the cache and the cache will not be invalidated, if
they change."*

So `@memory.cache def extract(dt): return _run(SQL_TEMPLATE.format(dt))` **will not re-run when
you edit `SQL_TEMPLATE`** — silently serving stale data during exactly the loop it was meant to
speed up. `functools.cache` is in-process only (dies at script exit). `diskcache` defaults to a
**1 GB `size_limit`** with LRS eviction and will silently evict a large extract.

**Recommend instead: manual parquet keyed on `sha256(source + normalised SQL + params +
version)`.** Key on the **connection identity** too, or dev and prod warehouses collide on the
same SQL. `tmp.replace(path)` for crash safety. A `REFRESH = False` module-level toggle (matches
the no-argparse rule). **Log the cache age on every hit** so staleness is never silent. Cache the
**raw** extract, never the derived frame. Never ship a cached run.

Honest invalidation matrix: query text ✅ · params ✅ · which server ✅ *only if keyed* ·
underlying data ❌ (TTL only) · semantics ❌ (manual version bump).

## Before/after levers

Dtype narrowing is a pure schema computation — no profiler needed: `Σ(width(dtype) × height)` vs
`estimated_size()`. Narrowing an ID column int64→int32 is a lossless 2× saving **if** the max
fits; check `arr.max() <= np.iinfo(np.int32).max` first, because overflow is silent.

String → `Enum` is the big one: measured, an 8-char column reports 8.00 B/row and its Enum
encoding 1.00 B/row — 8× on the reported number and ~16× on true memory once the BinaryView
struct is counted.

`pl.all().shrink_dtype()` is a **no-op on ≥1.33** — prefer `schema_overrides` at the source, or
shrink once when writing the parquet extract and let every later scan inherit the file's dtypes.
