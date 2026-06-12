# CLAUDE.md

## What This Repo Is

A dotfiles-style repository for Claude Code configuration. It stores the user's `~/.claude` managed files (CLAUDE.md, settings.json, skills) and deploys them via `install.sh`.

## Layout

- `claude/` — source tree mirrored into `~/.claude/` (CLAUDE.md, settings.json, skills/, agents/, statusline-command.sh)
- `marketplaces.txt` — one `name=org/repo` per line
- `plugins.txt` — one `plugin-name@marketplace-name` per line
- `install.sh` — deploy script

## Install

```bash
./install.sh
```

This script:
1. Backs up existing `~/.claude` managed files (once per day, keeps 7 days)
2. Deep-merges `claude/settings.json` into `~/.claude/settings.json` (jq object merge, with `permissions.allow`/`deny` unioned rather than replaced)
3. Mirrors `claude/skills/` and `claude/agents/` into `~/.claude/` with delete semantics (removed/renamed entries are pruned); copies the remaining top-level files verbatim
4. Registers plugin marketplaces from `marketplaces.txt` and installs plugins from `plugins.txt` via `claude plugin` CLI

## Key Details

- `settings.json` is the only file that gets merged (not overwritten) during install. All other files are copied directly.
- The merge deep-merges objects but **unions the `permissions.allow`/`deny` arrays** (repo entries first, then any live-only entries the user added via `/permissions`). Consequence: removing a permission from `claude/settings.json` does **not** remove it from the live file — edit the live file or restore from backup. Same for any other removed key (jq merge only adds/overwrites, never deletes keys).
- `skills/` and `agents/` are mirrored with delete (`rsync --delete`, or remove-then-copy as a fallback), so deleting a skill/agent here removes it from `~/.claude/` on the next install.
- `install.sh` **merges** `enabledPlugins` in `~/.claude/settings.json` from `plugins.txt` on every run (additive — removing a plugin from `plugins.txt` does not disable it in the live file).
- The backup only covers managed files (`CLAUDE.md`, `settings.json`, `skills`, `agents`, `statusline-command.sh`) — not sessions, cache, or history.
