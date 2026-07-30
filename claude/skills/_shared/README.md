# `_shared/` — helpers used by more than one skill

Not a skill. There is no `SKILL.md` here, so Claude Code never loads or triggers this
directory; it is a plain folder that `install.sh` mirrors to `~/.claude/skills/_shared/`
along with everything else under `skills/`.

Put something here when **two or more** skills use it. An asset used by exactly one skill
belongs in that skill's own folder.

**One folder per helper**, named after the helper, holding its script plus any files it
needs. Keeps the tree readable as more shared code lands here.

| Folder | Used by | What it does |
|---|---|---|
| `review_diff/` — `review-diff.sh` | `handoff`, `rolling-plan`, `realign-plan`, `agent-brief` | Opens an editable side-by-side diff in VS Code (`code --wait --diff`), blocks until the tab closes, then writes the right (editable) pane to the destination. Emptying the right pane cancels (exit 2). Falls back to a plain write when the `code` CLI is absent. |

Skills reference these by absolute installed path, e.g.:

```bash
~/.claude/skills/_shared/review_diff/review-diff.sh "$dest" "$proposed"
```

Because the path is shared, a change here changes every calling skill — grep for the
file name across `claude/skills/` before editing, and update the table when you add or
remove a helper.
