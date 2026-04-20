# Global Rules

## Core Principles

### Think Before Coding
- Plan first for non-trivial tasks. Get alignment before implementing. Keep asking questions until 95% confidence. Ask whether assumptions are correct.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### Simplicity First
- Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked. No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

### Surgical Changes
- Touch only what you must. Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken. Match existing style.
- If you notice unrelated dead code, mention it — don't delete it.
- Remove imports/variables/functions that YOUR changes made unused. Don't remove pre-existing dead code unless asked.
- Every changed line should trace directly to the request.

### Goal-Driven Execution
- Transform tasks into verifiable goals with success criteria.
- For multi-step tasks, state a brief plan: step → verify for each.
- For large implementations, suggest phased multi-agent approaches (competitive, collaborative, or mixed). Use separate branches for parallel agent work.

## Python
- Python 3.12+, `uv` only (never pip, conda, poetry)
- Google-style docstrings
- Type hints on function signatures; skip obvious local vars
- `logging` only — never `print()`. Library code: `logging.getLogger(__name__)`. Scripts/notebooks: project logger utility.
- Direct imports only — no try/except guards or `_HAS_X` flags
- Minimal comments: only for tricky logic, TODOs, assumptions, or non-obvious design choices
- Empty `__init__.py` files (no import code)
- Config-ready: parameters with sensible defaults, no config models
- pytest for testing. Write throwaway test scripts during implementation as needed.
