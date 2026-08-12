# Notebooks in Git

Two tools with different jobs: **nbstripout** keeps outputs out of history, **nbdime** makes whatever *is* in history diffable and mergeable. Offer them when a notebook first lands in a repo — configure neither unasked (SKILL.md rule).

## nbstripout — keep outputs out of commits

Paste-ready `.pre-commit-config.yaml` block:

```yaml
repos:
  - repo: https://github.com/kynan/nbstripout
    rev: 0.9.1        # released 2026-02-21
    hooks:
      - id: nbstripout
```

Caveats to state when offering it:

- Pre-commit mode **rewrites the working copy** — a notebook open in an editor loses its outputs the moment it is committed. That trade is the user's call.
- The alternative git-filter mode (`nbstripout --install`) strips only what git *stores* and leaves the working copy alone — but every collaborator must run it themselves; it cannot be set up for others automatically ("This is by design" — nbstripout README).
- Do **not** enable both modes at once.
- The zero-setup equivalent for a single delivery is `NBTOOL clean nb.ipynb`.

## nbdime — real notebook diffs and merges

nbdime (4.0.4, 2026-02-10, actively maintained) diffs and merges notebooks structurally instead of as raw JSON:

```bash
uv run --with nbdime nbdime config-git --enable    # per-repo; add --global for all repos
```

After that, `git diff` on `.ipynb` routes through `nbdiff` and merge conflicts through `nbmerge`; `nbdiff-web` / `nbmerge-web` open a browser UI.

**Interaction with nbstripout:** both tools write `*.ipynb diff=` lines into git attributes files, and the **last matching entry wins**. If both are enabled, check which attribute line survived before trusting either's diff output.
