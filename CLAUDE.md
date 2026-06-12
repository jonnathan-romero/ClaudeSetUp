# CLAUDE.md

## What This Repo Is

A dotfiles-style repository for Claude Code configuration. It stores the user's `~/.claude` managed files (CLAUDE.md, settings.json, skills) and deploys them via `install.sh`.

## Layout

- `claude/` — source tree mirrored into `~/.claude/` (CLAUDE.md, settings.json, skills/, agents/, statusline-command.sh, keybindings.json)
- `marketplaces.txt` — one `name=org/repo` per line
- `plugins.txt` — one `plugin-name@marketplace-name` per line
- `install.sh` — deploy script

## Install

```bash
./install.sh
```

This script:
1. Backs up existing `~/.claude` managed files (once per day, keeps 7 days)
2. Deep-merges `claude/settings.json` into `~/.claude/settings.json` (using `jq -s '.[0] * .[1]'`)
3. Copies everything else from `claude/` into `~/.claude/` verbatim
4. Registers plugin marketplaces from `marketplaces.txt` and installs plugins from `plugins.txt` via `claude plugin` CLI

## Key Details

- `settings.json` is the only file that gets merged (not overwritten) during install. All other files are copied directly.
- Because `settings.json` is deep-merged (`jq -s '.[0] * .[1]'`), removing a key from `claude/settings.json` won't remove it from `~/.claude/settings.json` — edit the live file or restore from backup.
- `install.sh` also rewrites `enabledPlugins` in `~/.claude/settings.json` from `plugins.txt` on every run.
- The backup only covers managed files (`CLAUDE.md`, `settings.json`, `skills`, `keybindings.json`, `statusline-command.sh`) — not sessions, cache, or history.
