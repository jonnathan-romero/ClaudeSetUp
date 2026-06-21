# Global Rules

## Response Style
- Lead with the answer. Conclusion first, then only the reasoning needed to trust it.
- Shortest complete response. Default to a few sentences or ≤5 bullets for simple things; expand only when the task is genuinely complex, multi-step, or I ask for detail.
- Brevity governs the final answer, not whether you reason the problem through. On hard problems, work it out fully, then give a tight answer — don't skip steps to look concise.
- Prose over bullet-fragments for explanations. Reserve markdown for code, real lists, and headings.
- No preamble or postamble: skip "Here is…", "Based on…", "I hope this helps"; don't restate my question.

## Research Agents
- When `web-researcher`, `doc-researcher`, or `codebase-explorer` returns a saved report/map path, ask whether to load the full file into context before continuing. `Read` the file only if the answer is yes — the digest already answers most questions; the full file is for context engineering (a clean synthesis is far cheaper to load than the raw sources). On a pure-locate task answered inline with no file, there's nothing to offer.

## Python
- Python 3.12+, `uv` only (never pip, conda, poetry)
- Never add dependency groups in `uv` (no `--group`/`[dependency-groups]`) — add to the main dependencies
- Google-style docstrings
- Type hints on function signatures; skip obvious local vars
- Never add `from __future__ import annotations` — Python 3.12+ evaluates our hint syntax natively, so it's redundant
- `logging` only — never `print()`. Library code: `logging.getLogger(__name__)`. Scripts/notebooks: project logger utility.
- Direct imports only — no try/except guards or `_HAS_X` flags
- Minimal succint comments: only for tricky logic, TODOs, assumptions, or non-obvious design choices
- Empty `__init__.py` files (no import code or comments)
- pytest for testing. Write throwaway test scripts during implementation as needed.
- No CLI arg parsing (`argparse`, `click`, `sys.argv`) in scripts — I run files in the IDE, not the terminal. Put runtime inputs as plain editable variables in `if __name__ == "__main__"`.
