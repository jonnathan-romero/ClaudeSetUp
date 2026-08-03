# Extraction: Snowflake, Snowpark, MSSQL, ClickHouse, REST

Versions verified 2026-08-03. These move fast — re-check before quoting.

The finding that dominates every source: **you pull far more than you use.** Measure
rows/bytes pulled vs rows/bytes actually read downstream before touching anything else.

## Snowflake connector (4.7.1)

**`pl.read_database(sql, conn)` is already Arrow-native for Snowflake.** Polars hard-codes a
`"snowflake"` entry in `ARROW_DRIVER_REGISTRY` mapping to `fetch_arrow_all`/`fetch_arrow_batches`.
So the generic *"use `read_database_uri`, connectorx/adbc optimise Arrow translation"* advice
**does not apply here** — do not propose it.

- **connectorx has never supported Snowflake** (README, hosted docs, zero code hits, and
  discussion #61 lists it as backlog since 2021). Yet Polars' own `read_database_uri` docstring
  shows a `snowflake://` example while defaulting `engine` to connectorx. That example only works
  with `engine="adbc"` — and ADBC defaults `use_high_precision=true`, silently mapping `NUMBER`
  to Decimal128 where the native connector gives float64. Set `use_high_precision=false` or
  declare the dtype change to the correctness gate; never let it flip unnoticed.
- **SQLAlchemy silently downgrades to row-wise** — it is absent from `ARROW_DRIVER_REGISTRY`.
  Pass the raw `SnowflakeConnection`.
- Polars swallows `"Apache Arrow format is not supported"` and falls back to rows. **Assert the
  Arrow path, don't assume it.**
- `cursor.query_result_format` **is not public API** — use `isinstance(batches[0], ArrowResultBatch)`.

**`get_result_batches()` is the star diagnostic.** `rowcount`, `compressed_size`,
`uncompressed_size` are *"available before you iterate over the result batch. You don't need to
fetch the subset of rows"*. Verified read-only — its one side effect is a telemetry log entry
(`GET_PARTITIONS_USED`) that will appear in the user's Snowflake telemetry; disclose that. This
is rows-pulled-vs-used, measured **without downloading**. Better than proposing `LIMIT`, which
*hides* true size. **Not reachable through `pl.read_database`** — it hides `cur.sfqid` and the
batches; instrumenting requires the raw cursor.

**`EXPLAIN` works over the connector and needs no running warehouse** → `partitionsTotal`,
`partitionsAssigned`, `bytesAssigned` (a free pruning check).
`SYSTEM$EXPLAIN_PLAN_JSON(query_id)` has a **14-day window** — the closest substitute for Query
Profile without `QUERY_HISTORY`. (Unverified whether it needs a grant overlapping QUERY_HISTORY —
check empirically.)

**`RESULT_SCAN('<sfqid>')` re-aggregates an already-paid-for result server-side** (24-hour
window): `SELECT COUNT(*) FROM TABLE(RESULT_SCAN('<sfqid>'))` measures a result without
re-running the query or downloading it — a propose-able fix as well as a diagnostic.

**Pinning extraction A/B arms to the same data:** live tables drift between arms — pin both with
time travel (`AT(TIMESTAMP => ...)`); where unavailable, compare on a keyed intersection and
report the drift instead of letting a shape mismatch read as a regression.

**Settings.** `client_prefetch_threads` is **silently clamped to 10**; passing 32 gives you 10 with
no warning. Undocumented but present: `client_fetch_threads` (cap 1024), `client_fetch_use_mp`.
Pass **all** session params to `connect()` — setting `autocommit` afterwards issues an extra
`ALTER SESSION` round trip (verified in source); `client_session_keep_alive` is likewise folded
in only at connect time. `pl.read_database(..., batch_size=...)` is **ignored** by the Snowflake
backend — the real chunking knob is the `CLIENT_RESULT_CHUNK_SIZE` session parameter (16–160,
default 160), passed via `session_parameters`.

**Traps.** `fetch_arrow_all()` returns **`None`** on an empty result — guard before
`pl.from_arrow`. Concatenating `fetch_arrow_batches()` needs `force_microsecond_precision=True`
or timestamps outside 1677–2262 raise a pyarrow schema mismatch — but the flag **truncates
sub-microsecond precision (scale 7–9)**, a value change the correctness gate must be told about
before it is enabled. The 2020 "up to 5×/10× Arrow" blog benchmark is **6.5 years and two major
versions stale** — measure, never cite it.

## Snowpark (1.54.0)

- **`df.queries` is free SQL inspection** — reads `self._plan.execution_queries` locally, no
  server round trip. This is how you show the SQL that will run. `df.explain()` is *different*:
  it runs `EXPLAIN` server-side, and only when the plan is a single statement.
- **`session.query_history(include_describe=True)`** — client-side context manager. Without
  `include_describe=True` you undercount round trips; Snowflake's own example shows 3 lines of
  user code → 2 server queries, one a hidden describe.
- **The official eager-action list names only 4 methods and is wrong.** The real surface also
  includes `to_pandas`, `to_arrow`, `to_arrow_batches`, `to_local_iterator`, `first`/`take`,
  `cache_result`, `explain`, `random_split`.
- **Hidden round trips:** `df.schema`, `df.columns`, `df.dtypes` — and the nasty one, **any
  failed attribute access**. `__getattr__` consults `self.columns`, so `hasattr(df, "to_arrow")`
  costs a DESCRIBE query. **Probe `type(df)` instead of `hasattr`.** Snowflake ships
  `reduce_describe_query_enabled` for this; it defaults to **False**.
- `to_arrow()` / `to_arrow_batches()` exist and call `fetch_arrow_all` directly (no pandas
  constructed), but the API-ref page 404s and issue #704 is still open — treat as lightly
  supported, keep a connector fallback. `to_arrow` requires the `[pandas]` extra (that is what
  pulls pyarrow; installing pandas ≠ computing in pandas).
- **Bugs, not slow paths:** `DataFrame.persist` doesn't exist (that's Spark — use
  `cache_result()`); `DataFrame` has **no `__iter__`**, so `for row in df:` is a bug.
- Long chains generate pathological SQL — `large_query_breakdown_enabled` exists for it. (Two
  distinct recursion fixes; don't conflate: 1.19.0 fixed a `RecursionError` in `df.dropna` with
  >500 columns, and the CTE-search recursion was fixed separately by an iterative rewrite,
  PR #1410.) Measure `len(df.queries["queries"][-1])` and paren nesting depth before/after a
  refactor. Remedies in order: project early → `cte_optimization_enabled = True` (default False;
  `sql_simplifier_enabled` already defaults **True** — don't propose enabling it) →
  `cache_result()` mid-chain, **only for a frame that is both expensive and reused**: it is a
  CTAS *write*, and with `auto_clean_up_temp_table_enabled` defaulting **False** the temp table
  lives until session end → `large_query_breakdown_enabled = True`.
- **Pushdown ladder, best → worst:** native `functions.*` / SQL expressions → `sqlExpr` →
  vectorized (pandas) UDF → scalar Python UDF (**row-by-row — flag any scalar UDF in a hot
  pipeline**) → `collect()` into client Python. Vectorized UDFs receive pandas **server-side
  inside Snowflake's sandbox** — the no-pandas rule is client-side and does not rule them out.
  But Snowflake's own lab found they *lose* on non-numeric operations.
- No official Snowpark-vs-connector benchmark exists in either direction. Don't claim one.

## MSSQL

**`pl.read_database` with a connection *string* routes to arrow-odbc (fast); passing a pyodbc
connection *object* silently falls into the row-wise path** — the commonest slow path.

**pyodbc has no bulk-read fast path at all.** Its C source shows one `SQLFetch` per row and
`SQL_ATTR_ROW_ARRAY_SIZE` appears **zero times**. Therefore:

- `cursor.arraysize` does **not** reduce read round-trips — it only supplies `fetchmany()`'s
  default argument. Advice of the form "set arraysize=10000 to speed up reads" is wrong.
- `fast_executemany` is **insert-only**. Setting it before a SELECT does nothing.
- `fetchmany` vs `fetchall` is a memory choice, not a speed choice.

**Arrow paths:** `arrow-odbc` 10.4.2 (what Polars uses for ODBC strings) or Microsoft's
`mssql-python` 1.12.0 (GA 2025-11-18, Arrow since 1.5.0).

**Disconfirming result worth knowing:** mssql-python's Arrow path on **Linux** is *slower* for
NVARCHAR — `1x nvarchar_100 → polars` went 2.196 s → 4.278 s (−1.9×), and the 20-column case
3.782 → 8.499 (−2.2×) — due to the UTF-16→UTF-8 conversion path. The same cases *win* on Windows.
Numeric and temporal win big (datetime 9.2×, datetimeoffset 22–26×). **The Arrow win is type- and
OS-dependent.**

**arrow-odbc's #1 MSSQL failure:** `NVARCHAR(MAX)` with default `max_text_size=None` sizes a
buffer for the theoretical maximum × 65535 rows → OOM. Always set `max_text_size` /
`max_binary_size` via `execute_options`.

**connectorx maps `DECIMAL` → float64** (*"cannot support precision larger than 28"*) and drops
`DATETIMEOFFSET` offsets — the wrong reader for money.

**Diagnostics with no DBA access:** `SET STATISTICS IO` / `SET STATISTICS TIME` — *"The SHOWPLAN
permission isn't required."* They reach Python via `cursor.messages` (pyodbc only —
mssql-python documents no `messages` attribute), but *"Each time `nextset()` is called, the
messages are deleted and replaced"* — harvest at every step, and know pyodbc #1434: when a
result set carries **both data and messages, the messages are not reported and the cursor
stops** — detect data via `cursor.description` and walk `nextset()` to drain every result set.
There is **no documented `Packet Size=` ODBC keyword**; `attrs_before={pyodbc.SQL_PACKET_SIZE:
16383}` or arrow-odbc's `packet_size=` are the candidates, but their end-to-end effect is
**unverified** — drivers may substitute a value (SQLSTATE `01S02`); check the effective size
before reporting the change as applied. Max for encrypted connections is 16,383 bytes.

**Measuring rows/bytes on pyodbc:** the C types are immutable — `pyodbc.Cursor.execute =
wrapper` raises `TypeError`, subclassing raises `TypeError`, instance attributes fail
(`tp_dictoffset = 0`). The only sanctioned route is wrapping module-level `pyodbc.connect` and
returning a **proxy**; count rows in the fetch proxy (pyodbc has **no byte counter** and
`rowcount` is unreliable for SELECT), size via `estimated_size()` after materialization. Inject
the proxy zero-edit via `sitecustomize.py` + `PYTHONPATH` (see `measurement.md`).

## ClickHouse (clickhouse-connect 1.6.0)

- **`query_df_arrow(dataframe_library=...)` defaults to `"pandas"`** — always pass `"polars"`.
  Same for `query_df_arrow_stream`.
- **`pl.read_database` does not recognise clickhouse-connect** (absent from
  `ARROW_DRIVER_REGISTRY`) → silently row-wise. Rewrite to `client.query_df_arrow(...)`.
- **Format choice dominates protocol choice** (~11.7× vs <1.2×). clickhouse-connect is HTTP-only
  but the wire format is Native/columnar — "HTTP" ≠ text protocol. Published benchmark (by the
  *competing* client, which strengthens it): 697k rows to PyArrow — clickhouse-connect
  `query_arrow` **1.28 s / 639 MB** vs `requests` + JSONEachRow **15.04 s parsed**, and
  **2.84 GB just to hold the raw response** (two rows of the same benchmark, not one
  measurement).
- **`QueryResult.summary`** decodes `X-ClickHouse-Summary`: `read_rows`, `read_bytes`,
  `result_rows`, `result_bytes` (RAM used to hold the result — **not** wire bytes),
  `memory_usage`, `elapsed_ns` (all JSON strings). `read_*` is what the server scanned; the
  zero-privilege pruning check is `read_rows` vs `total_rows_to_read` from the same header — a
  ratio near 1.0 means no pruning happened (`EXPLAIN ESTIMATE` is the other zero-cost check).
  **But the Arrow methods discard the headers**, and `query_arrow` still pays
  `wait_end_of_query=1` server-side buffering with none of the benefit. The summary only comes
  from `client.query()` — a **second execution with different cache state**, so never attribute
  its `elapsed_ns` to the real call. To attribute the *actual* Arrow-path query, set an explicit
  `query_id` and read `system.query_log`.
- `output_format_arrow_low_cardinality_as_dictionary` defaults to `0` — easy win.
  `DateTime`→`UINT32` and `Date32`→`UINT16` in Arrow (doc-sourced; verify against the server).
- **Don't blanket-flag** `FINAL` (*"On a well-merged table with a single part in a partition,
  FINAL would be just as fast"*) or a missing `PREWHERE` (on by default). **Gate the "small table
  on the right" JOIN advice on `SELECT version()`** — auto-reordering landed in 24.12. `OR`
  inside a JOIN `ON` *is* always worth flagging (one hash table per branch).
- Use `query_arrow_stream` for bounded memory; `with` is mandatory. **Require
  clickhouse-connect ≥ 1.4.0 for any streaming proposal** — below that a dropped connection
  mid-stream is silently treated as a complete result: truncated data, no exception. Slow
  per-batch compute between reads is the other common mid-stream killer — `http_buffer_size`
  (default 10 MiB) is the usual fix for stream-then-compute pipelines. For a `readonly=1` user,
  query-injected settings are **silently dropped** (client logs a warning) — verify a proposed
  setting took effect; don't assume.

## REST APIs

Priority order — the first item beats every other one combined:

1. **Find a bulk/export endpoint or an incremental filter.** Eliminates ~all requests.
2. **Set a timeout.** `requests` has **none by default** — a P1 bug, not a tuning knob.
3. **Reuse one Session/Client** — saves ~2 RTT per request (TCP + TLS 1.3), one line.
4. **Raise `per_page` to the documented max** — 3–10× fewer round trips, one parameter. APIs
   **silently clamp** (ask GitHub for 1000, get 100, no warning): read the actual page size back
   from the response before deriving round-trip counts, or the extraction arithmetic is 10× off.
5. Push filters server-side; stop early.
6. **Bounded concurrency.** Size by Little's Law: `concurrency = throughput × latency`.
7. **Token bucket + `Retry-After`-aware full-jitter retry** — makes 6 safe rather than a 429
   generator. Full Jitter: `sleep = random(0, min(cap, base * 2 ** attempt))`.
8. Dev-loop cache. 9. `json` → `orjson`. 10. Explicit Polars schema. 11. **Only then** HTTP/2.

**Structural findings.**

- **Cursor pagination cannot be parallelized** — page N+1's request needs page N's cursor, a hard
  floor of `n_pages × latency`. Offset pagination *is* parallelizable but degrades O(N²)
  server-side and drifts under concurrent writes. The real fix is **partitioning the keyspace**
  (date ranges, ID bands) so N partitions each walk their own cursor. That is a restructuring
  proposal, not a tuning one — say so.
- **Threads beat async for an otherwise-synchronous script.** A `ThreadPoolExecutor` leaves
  `fetch()`'s body and every caller untouched; async turns all of them into `async def`, and the
  synchronous Polars stage then has to be exiled to an executor anyway. *"The GIL is always
  released when doing I/O."* One caveat: `requests.Session` is **not documented thread-safe** —
  use one Session per thread via `threading.local()`, or `httpx.Client`, which is designed for
  concurrent use.
- **Free-threading is a no-op for extraction** — the GIL was never the bottleneck there, and
  single-threaded code pays 5–10%.
- **HTTP/2 is last and sometimes slower.** httpx's maintainer: *"HTTP/2 isn't 'faster' than
  HTTP/1.1. In fact, because it's computationally more complex… part of the request/response
  handling will be slower."* A user measured ~1.3× slower sync. Check `response.http_version` —
  it silently falls back on h1.1-only servers.

**Two knobs people conflate:** concurrency ceiling (in flight at once → semaphore / `max_workers`)
vs rate limit (per unit time → token bucket). **Semaphore OUTSIDE, limiter INSIDE** — inverted,
tasks draw rate tokens then queue on the semaphore and all fire at once, bursting past the limit.

**Pool sizing:** the connection pool must be ≥ the concurrency ceiling or workers queue on the
pool. httpx defaults `max_connections=100`, `max_keepalive_connections=20`; `requests`'
`HTTPAdapter` defaults 10/10 and silently throttles a wider thread pool.

**Never read `response.content` in an instrumentation wrapper** — under `stream=True` it silently
consumes the user's stream. Use `Content-Length`.

**Retry only what should be retried.** 429 (RFC 6585) and 503 → yes, honour `Retry-After`, which
*"can be either an HTTP-date or a number of seconds"* — `int()` on it raises `ValueError`. 5xx
only for idempotent methods. **4xx → no**; retrying burns quota and hides the bug. Exception:
403 with `x-ratelimit-remaining: 0` (GitHub) *is* a rate limit.

**Parsing is the hidden second bottleneck** once the network is parallelized: ~25 MB file —
stdlib `json` 420 ms / 136 MB, orjson 280 ms / 114 MB, msgspec 90 ms / 39 MB (the big msgspec win
needs `msgspec.Struct`; schemaless it is roughly par with orjson). **And parse inside the
workers, not after the pull** — per-page parse cost hides behind the other workers' network
waits, and peak memory caps at roughly one page per worker instead of the whole result set.

**Library staleness:** `backoff` last shipped 2022-10-05 — prefer `stamina` or `tenacity`.
`pyrate-limiter` 4.x moved blocking control to `blocking=` on `try_acquire()`; v2/v3
`raise_when_fail`/`max_delay` advice is stale.

## Anti-patterns to detect

`SELECT *` then filtering in Python · aggregating client-side what the server aggregates orders
of magnitude faster · per-row queries in a loop (N+1) · no `LIMIT` during development · pulling
wide then `select()`ing narrow · `requests.get` in a for loop · a new Session per call · no
timeout · `time.sleep()` as a rate limiter · re-fetching unchanged data every run · fetch-all-
pages-then-filter · `pl.concat` inside the loop (O(n²)) · relying on `infer_schema_length=100`
on heterogeneous pages · `stream=True` without draining.
