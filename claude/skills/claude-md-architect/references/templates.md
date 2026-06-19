# Starter CLAUDE.md templates

Use as a starting skeleton. Trim aggressively — the goal is the
shortest CLAUDE.md that still prevents real mistakes.

## Contents

- Generic skeleton
- Python (primary)
- TypeScript / JavaScript stub
- Rust stub
- Go stub
- Trim heuristic

## Generic skeleton

````markdown
# [Project name]

[One-sentence description of what this is.]

## Stack
- [Language and version]
- [Runtime / framework]
- [Notable libraries]

## Commands
```bash
# Install
[install command]
# Test
[test command]
# Lint
[lint command]
```

## Architecture
[One paragraph: where the code lives, how data flows, what's
non-obvious.]

## Style
- [Rule 1]
- [Rule 2]

## Gotchas
- [Specific past-mistake-prevention rules]
````

## Python (primary)

````markdown
# [Project name]

## Stack
- Python 3.12+
- `uv` for env / dependency management (never pip, conda, poetry)
- pytest for testing

## Commands
```bash
uv sync
uv run pytest
uv run ruff check
uv run ruff format
```

## Style
- Type hints on function signatures; skip obvious local vars
- Google-style docstrings
- `logging.getLogger(__name__)` for library code; `print()` only in
  one-off scripts
- Direct imports — no try/except guards or `_HAS_X` flags
- Empty `__init__.py` files
- Minimal comments: only for tricky logic, TODOs, assumptions, or
  non-obvious design choices

## Architecture
- `src/` for library code
- `tests/` for pytest suites
- `scripts/` for one-off CLI utilities

## Gotchas
- [Project-specific things Claude has gotten wrong before]
````

## TypeScript / JavaScript stub

````markdown
## Stack
- Node [version], pnpm
- TypeScript strict mode
- [framework]

## Commands
```bash
pnpm install
pnpm test
pnpm lint
```

## Style
- Functional components; hooks at top of file
- `@/*` import alias for src
- No `any` — use `unknown` and narrow
````

## Rust stub

````markdown
## Stack
- Rust 2024 edition
- cargo workspaces

## Commands
```bash
cargo check --all-features
cargo test --all-features
cargo clippy -- -D warnings
```

## Style
- All clippy warnings are errors
- `tempfile::tempdir()` for test fixtures
- Serialize model types
````

## Go stub

````markdown
## Stack
- Go [version]
- go modules

## Commands
```bash
go test -race ./...
go vet ./...
golangci-lint run
```

## Style
- Race detector required for tests
- Test every exported function and error case
- Reserve CLAUDE.md for architectural judgment; let `go vet` and
  `staticcheck` enforce syntax/naming.
````

## Trim heuristic

After drafting, count lines. If over 120, ask:

1. Is anything inferable from reading two files? Delete.
2. Any rule the model already follows by default? Delete.
3. Any "DO X every time"? Move to a hook.
4. Any multi-step procedure? Move to a Skill.

Target landing: 50–150 lines.

## References

- https://code.claude.com/docs/en/memory.md
- https://github.com/anthropics/skills (notable examples)
- https://github.com/josix/awesome-claude-md
