# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A dotfiles-style repository for Claude Code configuration. It stores the user's `~/.claude` managed files (CLAUDE.md, settings.json, skills) and deploys them via `install.sh`.

## Install

```bash
./install.sh
```

This script:
1. Backs up existing `~/.claude` managed files (once per day, keeps 30 days)
2. Deep-merges `claude/settings.json` into `~/.claude/settings.json` (using `jq -s '.[0] * .[1]'`)
3. Copies everything else from `claude/` into `~/.claude/` verbatim
4. Registers plugin marketplaces from `marketplaces.txt` and installs plugins from `plugins.txt` via `claude plugin` CLI

## Key Details

- `settings.json` is the only file that gets merged (not overwritten) during install. All other files are copied directly.
- The backup only covers managed files (`CLAUDE.md`, `settings.json`, `skills`, `keybindings.json`, `statusline-command.sh`) — not sessions, cache, or history.
- Plugin lines use the format `plugin-name@marketplace-name` where marketplace names map to GitHub repos defined in `marketplaces.txt`.
