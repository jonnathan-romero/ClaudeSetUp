#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
BACKUP_BASE="$CLAUDE_DIR/backups"
BACKUP_DIR="$BACKUP_BASE/$(date +%Y-%m-%d)"
MAX_BACKUPS=7

log() { printf '[install] %s\n' "$1"; }

# --- Prune old backups beyond $MAX_BACKUPS (before adding today's) ---
if [ -d "$BACKUP_BASE" ]; then
    backup_count=$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d | wc -l)
    # Leave room for today's backup if we're about to create one
    keep=$(( MAX_BACKUPS - 1 ))
    if [ "$backup_count" -gt "$keep" ]; then
        find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d | sort | head -n $(( backup_count - keep )) | while read -r old; do
            rm -rf "$old"
            log "Pruned old backup: $(basename "$old")"
        done
    fi
fi

# --- Backup ~/.claude once per day ---
if [ ! -d "$CLAUDE_DIR" ]; then
    log "No existing ~/.claude — nothing to back up"
elif [ -d "$BACKUP_DIR" ]; then
    log "Backup already exists for today (skipping)"
else
    mkdir -p "$BACKUP_DIR"
    # Back up only the files we manage (not sessions, cache, history, etc.)
    for item in CLAUDE.md settings.json skills agents statusline-command.sh; do
        [ -e "$CLAUDE_DIR/$item" ] && cp -r "$CLAUDE_DIR/$item" "$BACKUP_DIR/"
    done
    log "Backed up managed files to $BACKUP_DIR"
fi

# --- Sync claude/ directory into ~/.claude/ ---
log "Installing configuration files..."
mkdir -p "$CLAUDE_DIR"

# settings.json gets special treatment: deep-merge repo into live.
# jq's `*` deep-merges objects but REPLACES arrays, which would wipe any
# permission rules the user added live (via /permissions). So merge the
# objects, then rebuild permissions.allow/deny as repo-order ++ live-only
# extras (no dupes) — repo entries win order, live-only entries are kept.
if [ -f "$SCRIPT_DIR/claude/settings.json" ]; then
    if [ -f "$CLAUDE_DIR/settings.json" ]; then
        TMP="$(mktemp)"
        jq -s '
            .[0] as $live | .[1] as $repo
            | ($live * $repo)
            | .permissions.allow = (($repo.permissions.allow // []) + (($live.permissions.allow // []) - ($repo.permissions.allow // [])))
            | .permissions.deny  = (($repo.permissions.deny  // []) + (($live.permissions.deny  // []) - ($repo.permissions.deny  // [])))
        ' "$CLAUDE_DIR/settings.json" "$SCRIPT_DIR/claude/settings.json" > "$TMP"
        mv "$TMP" "$CLAUDE_DIR/settings.json"
        log "Deep-merged settings.json (permission arrays unioned)"
    else
        cp "$SCRIPT_DIR/claude/settings.json" "$CLAUDE_DIR/settings.json"
        log "Installed settings.json"
    fi
fi

# Fully-managed subtrees: mirror with delete semantics so renamed/removed
# skills and agents don't linger in ~/.claude. Prefer rsync; fall back to
# remove-then-copy. The daily backup above covers a mid-copy failure.
for subtree in skills agents; do
    [ -d "$SCRIPT_DIR/claude/$subtree" ] || continue
    if command -v rsync &>/dev/null; then
        rsync -a --delete --exclude '__pycache__' --exclude '*.py[cod]' \
            "$SCRIPT_DIR/claude/$subtree/" "$CLAUDE_DIR/$subtree/"
    else
        rm -rf "${CLAUDE_DIR:?}/$subtree"
        cp -rp "$SCRIPT_DIR/claude/$subtree" "$CLAUDE_DIR/$subtree"
        find "$CLAUDE_DIR/$subtree" -name '__pycache__' -type d -prune -exec rm -rf {} +
    fi
    log "Synced $subtree/ (with delete)"
done

# Remaining top-level managed files: straight copy (preserve mode so
# executables stay executable). skills/ and agents/ handled above.
find "$SCRIPT_DIR/claude" -mindepth 1 -maxdepth 1 -type f -not -name "settings.json" | while IFS= read -r src; do
    rel="${src#$SCRIPT_DIR/claude/}"
    dest="$CLAUDE_DIR/$rel"
    cp -fp "$src" "$dest"
    log "Installed $rel"
done

# --- Wire up rga office-search adapters (xlsx/pptx) for the file-search skill ---
SETUP_OFFICE="$CLAUDE_DIR/skills/file-search/scripts/setup_office_search.py"
if [ -f "$SETUP_OFFICE" ]; then
    if command -v rga &>/dev/null && command -v uv &>/dev/null; then
        if uv run "$SETUP_OFFICE"; then
            log "Registered rga xlsx/pptx adapters"
        else
            log "WARNING: rga office-adapter setup failed"
        fi
    else
        log "Skipping rga office adapters (need 'rga' and 'uv' on PATH)"
    fi
fi

# --- Install plugins ---
# Config files are already installed at this point; plugins are the only
# remaining step, so a missing CLI is a partial skip, not a failure.
if ! command -v claude &>/dev/null; then
    log "WARNING: 'claude' CLI not found in PATH — config installed, skipping plugins."
    log "Done (without plugins)!"
    exit 0
fi

# Register marketplaces from marketplaces.txt
# Format: name=owner/repo. The `name` is informational (the marketplace's
# self-declared identifier in its .claude-plugin manifest is what plugins.txt
# must reference); we only pass `repo` to the CLI.
if [ -f "$SCRIPT_DIR/marketplaces.txt" ]; then
    log "Registering marketplaces..."
    grep -v '^\s*#' "$SCRIPT_DIR/marketplaces.txt" | grep -v '^\s*$' | while IFS='=' read -r name repo; do
        log "  $name ($repo)"
        if ! out=$(claude plugin marketplace add "$repo" 2>&1); then
            case "$out" in
                *already*) ;;
                *) log "    WARNING: $out" ;;
            esac
        fi
    done
fi

# Install plugins from plugins.txt
if [ -f "$SCRIPT_DIR/plugins.txt" ]; then
    log "Installing plugins..."
    grep -v '^\s*#' "$SCRIPT_DIR/plugins.txt" | grep -v '^\s*$' | while read -r plugin; do
        log "  $plugin"
        if ! out=$(claude plugin install "$plugin" 2>&1); then
            case "$out" in
                *already*) log "    (already installed)" ;;
                *) log "    WARNING: $out" ;;
            esac
        fi
    done

    # Enable plugins in settings.json (merge into existing enabledPlugins)
    log "Enabling plugins in settings.json..."
    ENABLED_JSON=$(grep -v '^\s*#' "$SCRIPT_DIR/plugins.txt" | grep -v '^\s*$' \
        | jq -R -s 'split("\n") | map(select(length > 0)) | map({(.): true}) | add // {}')
    TMP="$(mktemp)"
    jq --argjson enabled "$ENABLED_JSON" \
        '.enabledPlugins = ((.enabledPlugins // {}) + $enabled)' \
        "$CLAUDE_DIR/settings.json" > "$TMP"
    mv "$TMP" "$CLAUDE_DIR/settings.json"
fi

log "Done!"
