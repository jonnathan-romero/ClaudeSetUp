# Global Rules

## Core Principles

### Think Before Coding
- Plan first for non-trivial tasks. Get alignment before implementing. Ask follow-ups whenever scope, naming, or interfaces are ambiguous. Confirm assumptions explicitly.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### Simplicity First
- Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked. No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- When a draft feels long, look for the simpler shape and rewrite before showing it.

### Surgical Changes
- Touch only what the task requires. Match existing style. Leave adjacent code, comments, and formatting alone unless the request asks otherwise.
- If you notice unrelated dead code, mention it — don't delete it.
- Remove imports/variables/functions that your changes made unused. Leave pre-existing dead code alone unless asked.
- Every changed line should trace directly to the request.

### Goal-Driven Execution
- Transform tasks into verifiable goals with success criteria.
- For multi-step tasks, state a brief plan: step → verify for each.
- For large implementations, suggest phased multi-agent approaches (competitive, collaborative, or mixed). Use separate branches for parallel agent work.

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
- Google-style docstrings
- Type hints on function signatures; skip obvious local vars
- Never add `from __future__ import annotations` — Python 3.12+ evaluates our hint syntax natively, so it's redundant
- `logging` only — never `print()`. Library code: `logging.getLogger(__name__)`. Scripts/notebooks: project logger utility.
- Direct imports only — no try/except guards or `_HAS_X` flags
- Minimal succint comments: only for tricky logic, TODOs, assumptions, or non-obvious design choices
- Empty `__init__.py` files (no import code or comments)
- pytest for testing. Write throwaway test scripts during implementation as needed.
- No CLI arg parsing (`argparse`, `click`, `sys.argv`) in scripts — I run files in the IDE, not the terminal. Put runtime inputs as plain editable variables in `if __name__ == "__main__"`.
