# Logging reference

Backing detail for `add-logging/SKILL.md`. Load only when you need the exact linter codes, the wrapper-attribution rule, or the structured-logging tradeoff. Every claim is sourced.

## Contents

- [Linter rule codes (Ruff + Pylint)](#linter-rule-codes)
- [Lazy `%` vs f-strings — the real rationale + the counter-argument](#lazy--vs-f-strings)
- [Exceptions inside `except`](#exceptions-inside-except)
- [Wrapper attribution — `stacklevel`](#wrapper-attribution)
- [Hot loops + `isEnabledFor`](#hot-loops)
- [Log injection — CWE-117](#log-injection-cwe-117)
- [Structured logging positioning](#structured-logging)
- [Sources](#sources)

## Linter rule codes

Naming the code makes "use lazy %" actionable — the user can wire it to their linter.

| Code | Tool | Meaning |
|---|---|---|
| `G001` | Ruff `flake8-logging-format` | logging statement uses `str.format` |
| `G002` | Ruff `flake8-logging-format` | logging statement uses `%`-format via `%` operator (pre-format) instead of args |
| `G003` | Ruff `flake8-logging-format` | logging statement uses `+` string concatenation |
| `G004` | Ruff `flake8-logging-format` | logging statement uses an **f-string** (the common one) |
| `G201` | Ruff `flake8-logging-format` | `logging.error(..., exc_info=True)` instead of `logging.exception` |
| `LOG007` | Ruff `flake8-logging` | `logging.exception(..., exc_info=False)` — traceback suppressed, use `error` |
| `LOG015` | Ruff `flake8-logging` | logging call on the **root** logger (use a module `getLogger(__name__)`) |
| `W1201` | Pylint `logging-not-lazy` | use lazy `%`-formatting in logging functions |
| `W1203` | Pylint `logging-fstring-interpolation` | use lazy `%`-formatting — an f-string was used |

## Lazy % vs f-strings

The rationale: with `logger.info("x=%s", x)` the interpolation is *deferred until it cannot be avoided* — if the record is filtered by level, no formatting happens. An f-string (`f"x={x}"`) is built eagerly at the call site regardless of whether the record is ever emitted. Python HOWTO §Optimization: *"Formatting of message arguments is deferred until it cannot be avoided."*

Counter-argument (represent it fairly): some teams disable `W1203`/`G004` and standardize on f-strings for readability and consistency, on the grounds that the perf gain is negligible for most logging. Treat f-strings as a **project-config opt-out**, not a stdlib recommendation — match a codebase that has clearly chosen them, default to `%` otherwise.

## Exceptions inside except

- `logger.exception("msg")` — logs at ERROR **with** the current traceback. Only meaningful inside an exception handler.
- `logger.error("msg", exc_info=True)` — equivalent, but Ruff `G201` prefers `exception()` as clearer.
- `logger.error("msg")` — use when you deliberately do **not** want a traceback. Do not write `exception(..., exc_info=False)` to suppress it (Ruff `LOG007`); just use `error`.

## Wrapper attribution

Only relevant if logs are routed through a helper (not the default direct-call case). When a helper wraps `logger.*`, `funcName`/`lineno` in the record point at the helper, not the real caller. Pass `stacklevel=2` (or deeper) so attribution points at the true call site. Added in Python 3.8.

## Hot loops

Avoid DEBUG calls inside tight loops. When building the *arguments* is expensive (not just the message), guard:

```python
if logger.isEnabledFor(logging.DEBUG):
    logger.debug("state=%s", expensive_snapshot())
```

Plain `%`-args (`logger.debug("i=%d", i)`) need no guard — formatting is already deferred; the guard is only to skip expensive **argument construction**.

## Log injection — CWE-117

CWE-117 "Improper Output Neutralization for Logs": code *"constructs a log message from external input, but ... does not neutralize ... special elements."* CRLF / `%0a` newlines in untrusted input let an attacker *"forge log entries"* (OWASP Log Injection). Mitigations: allow-list validation or newline-escaping of untrusted values, or structured logging so a field value can't break the line.

In this skill's insertion-only mode you do **not** insert a sanitizer (that is a logic change). Instead prefer logging typed / ID fields, and flag any raw untrusted free-text you log so the user decides.

## Structured logging

- **stdlib:** attach context via `extra={...}` (a dict merged into the record) rather than baking it into the message string — keeps fields machine-parseable and formatting deferred.
- **structlog / JSON:** for machine-consumed server logs, structured output gives *"a meaningful dictionary instead of an opaque string."* Plain string messages remain fine for CLI / console tools.

This skill emits plain `%`-style messages by default; only reach for `extra={}` or structured output when the file already uses that style.

## Sources

- Python logging HOWTO — levels, library-config guidance, Optimization: https://docs.python.org/3/howto/logging.html
- Python logging cookbook — patterns to avoid: https://docs.python.org/3/howto/logging-cookbook.html
- Python logging reference — `exception()`, `stacklevel`: https://docs.python.org/3/library/logging.html
- Ruff rules index (search the code to reach each page): https://docs.astral.sh/ruff/rules/ — covers `flake8-logging-format` (`G001`–`G004`, `G201`) and `flake8-logging` (`LOG007`, `LOG015`). Verified deep link, G004: https://docs.astral.sh/ruff/rules/logging-f-string/
- Pylint `W1201` / `W1203`: https://pylint.readthedocs.io/
- CWE-117: https://cwe.mitre.org/data/definitions/117.html
- OWASP Log Injection: https://owasp.org/www-community/attacks/Log_Injection
- structlog rationale: https://www.structlog.org/en/stable/why.html
