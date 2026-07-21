---
name: add-logging
description: Add smart logging (logger.debug / info / warning / error) to a specified Python file. ALWAYS trigger when the user says "add logging to this file", "add logger.info/debug/warning/error", "instrument this file with logging", "put log statements in <file.py>", "add log lines here", "wire up logging for this module", or names a .py file and asks to add/insert logging. Reads the target file plus one or two hops of surrounding code (callers and callees) to place logs at the right levels, adds `logger = logging.getLogger(__name__)` at the top, and uses lazy %-formatting. Insertion-only — adds logging lines, never edits existing logic. Do NOT use to configure project-wide logging (handlers / basicConfig / dictConfig), to remove or clean up existing logs, to set up a logging config file, or for general code review / bug hunting.
argument-hint: "Path to the .py file to instrument with logging"
---

Add logging to the one Python file the user names (`$ARGUMENTS`). Instrument that **one file**; read around it to make good calls, but edit only that file — and within it, **add logging only, never change existing logic**.

**Scope — insertion-only.** Every edit is a pure addition: `import logging` if missing, the module-level `logger = …` line, and `logger.<level>(...)` calls. Do not delete, reorder, or rewrite any existing line. Do **not** refactor to capture a value (`x = f(); logger.debug(...); return x`) — that is a logic change; skip that particular log instead. This constraint is what makes the change safe to trust and trivial to verify.

**Mental model:** add the logs a careful engineer wants when debugging this file in production at 3am — the significant lifecycle events, which branch was taken, the external call that failed — without adding noise and without changing what the code does. Default to restraint: a handful of well-placed lines beats narrating every statement.

## Set up the logger

- Ensure `import logging` is present (add it among the stdlib imports if missing).
- Add, after the imports and before the first `def`/`class`: `logger = logging.getLogger(__name__)`.
- **Library / package module** (anything importable under a package): use `logging.getLogger(__name__)`. Never add `basicConfig()`, handlers, or `setLevel` on the root logger — configuring output is the application entrypoint's job, not a module's. (Ruff `LOG015` flags root-logger calls.)
- **Script / entrypoint / notebook** (a `__main__` runner): detect and match the project's own logger utility if it ships one (commonly a `log_utils` module exposing a `get_logger(name)` — check the imports of sibling scripts). Otherwise `logging.getLogger(__name__)`.
- If a module-level `logger` already exists, reuse it — never add a second.

## Process

1. **Understand the file.** Read it top to bottom: the public surface, control flow, the error / `except` paths, external I/O (network, disk, DB, subprocess), branch and fallback points, and loop boundaries. These are where a log earns its place.
2. **Read one or two hops of surrounding code** — the callers / importers upstream and the functions it calls downstream — for two reasons: (a) learn the project's existing logging style and match it (`getLogger` vs project util; lazy `%` vs f-strings; message tone), and (b) avoid double-logging something a caller or callee already records. Do not map the whole repo.
3. **Insert the logger line** (see above).
4. **Add logging** at the right levels and places (rubrics below).
5. **Verify** (see below), then show the diff and let the user review — placement is a judgment call, so their read of the diff is the real acceptance test.

## Levels — where each belongs

Official stdlib semantics (Python logging HOWTO):

| Level | Meaning | Add it at |
|---|---|---|
| DEBUG | diagnostic detail for debugging | key intermediate values, which branch ran, loop-boundary counts, cache hit/miss |
| INFO | confirmation things work as expected | start / end of a significant operation, resource opened / closed, item counts, config chosen |
| WARNING | something unexpected or a near-future problem; the code still works | fallback taken, retry, deprecated path, empty result where one was expected, nearing a limit |
| ERROR | a function couldn't do its job | inside `except` for a real failure, a required resource missing, an operation returning failure |
| CRITICAL | the program may not be able to continue | rare — unrecoverable startup / config failure |

If torn between two levels, pick the quieter one. Prefer INFO for the few events that matter and DEBUG for detail.

## Message formatting — non-negotiable

- **Lazy `%`-style, never f-strings:** `logger.info("indexed %d docs into %s", n, name)` — not `logger.info(f"indexed {n} docs")`. f-strings format eagerly even when the record is never emitted; `%`-args defer formatting until (and unless) a handler fires. This is what Ruff `G004` and Pylint `W1203` enforce. If the file already uses f-strings in logs project-wide, match that; otherwise default to `%`.
- **Inside `except`:** use `logger.exception("...")` — it captures the traceback and is only valid in an exception handler. Use `logger.error("...")` (no traceback) only when you deliberately don't want one; never `exception(..., exc_info=False)`.
- **Expensive-to-build DEBUG args:** guard with `if logger.isEnabledFor(logging.DEBUG):`. Plain `%`-args need no guard — already deferred.

Full linter-code catalog, `stacklevel` for wrappers, and sources: [`references/logging-reference.md`](references/logging-reference.md).

## Footgun — never evaluate a side effect in a log argument

This is the one way an "insertion-only" change can still alter behavior. A log argument must be a **side-effect-free read** — a parameter, an attribute, `len(x)`, or an already-computed local. Never call anything in a log arg that mutates state, consumes an iterator, or does I/O:

- ✗ `logger.debug("popped %s", stack.pop())` — mutates
- ✗ `logger.debug("next: %s", next(it))` — consumes the iterator
- ✗ `logger.debug("body: %s", resp.read())` — I/O + consumes
- ✓ `logger.debug("stack depth %d", len(stack))`

If the value you want is only reachable by calling something with a side effect, skip that log.

## Untrusted input (CWE-117) — flag, don't sanitize

Logging attacker-controlled strings raw is log injection (CWE-117): embedded newlines let someone forge log lines. But sanitizing is a *logic change*, which insertion-only forbids. So **prefer logging typed / ID fields over raw free-text** (`logger.info("user id=%s", user.id)`, not the raw display name). Where untrusted free-text genuinely must be logged, add the call and **flag it in your summary** so the user can decide on sanitization — never silently wrap it in an escaper.

## Do not

- Change, reorder, or delete any existing line — logging additions only.
- Log secrets, credentials, tokens, full auth headers, or PII.
- Add logs inside tight / hot loops — log the aggregate before or after instead.
- Double-log what a caller or callee already records.
- Instrument trivial pure functions, dunder methods, or `__init__.py` — no signal.

## Verify

Because the change is insertion-only, the invariant is **pure addition** — prove it:

1. **Parses:** `python -m py_compile <file>` (or import it).
2. **Nothing removed or rewritten:** `git diff -- <file>` shows only added (`+`) lines, and every added line is `import logging`, the `logger = …` assignment, or a `logger.<level>(...)` call. Any `-` line (other than a `+`/`-` pair that is purely re-indentation you introduced — avoid even that) is a bug — revert it. If the file isn't under git, diff against a copy you saved before editing.
3. **No side-effect args:** re-scan every added log call against the footgun rule above.

Then show the diff and report: what you logged and at which levels, anything flagged for sanitization (CWE-117), and anything you deliberately left un-logged.
