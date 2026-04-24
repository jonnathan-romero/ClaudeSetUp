#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
BACKUP_BASE="$CLAUDE_DIR/backups"
BACKUP_DIR="$BACKUP_BASE/$(date +%Y-%m-%d)"
MAX_BACKUPS=30

log() { printf '[install] %s\n' "$1"; }

# --- Backup ~/.claude once per day ---
if [ -d "$CLAUDE_DIR" ] && [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    # Back up only the files we manage (not sessions, cache, history, etc.)
    for item in CLAUDE.md settings.json skills keybindings.json statusline-command.sh; do
        [ -e "$CLAUDE_DIR/$item" ] && cp -r "$CLAUDE_DIR/$item" "$BACKUP_DIR/"
    done
    log "Backed up managed files to $BACKUP_DIR"
else
    log "Backup already exists for today (skipping)"
fi

# --- Prune old backups beyond $MAX_BACKUPS ---
if [ -d "$BACKUP_BASE" ]; then
    backup_count=$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d | wc -l)
    if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
        find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d | sort | head -n $(( backup_count - MAX_BACKUPS )) | while read -r old; do
            rm -rf "$old"
            log "Pruned old backup: $(basename "$old")"
        done
    fi
fi

# --- Sync claude/ directory into ~/.claude/ ---
log "Installing configuration files..."
mkdir -p "$CLAUDE_DIR"

# settings.json gets special treatment: deep-merge repo into live
if [ -f "$SCRIPT_DIR/claude/settings.json" ]; then
    if [ -f "$CLAUDE_DIR/settings.json" ]; then
        TMP="$(mktemp)"
        jq -s '.[0] * .[1]' "$CLAUDE_DIR/settings.json" "$SCRIPT_DIR/claude/settings.json" > "$TMP"
        mv "$TMP" "$CLAUDE_DIR/settings.json"
        log "Deep-merged settings.json"
    else
        cp "$SCRIPT_DIR/claude/settings.json" "$CLAUDE_DIR/settings.json"
        log "Installed settings.json"
    fi
fi

# Everything else: straight copy
find "$SCRIPT_DIR/claude" -mindepth 1 -not -name "settings.json" -not -path "*/settings.json" | while read -r src; do
    rel="${src#$SCRIPT_DIR/claude/}"
    dest="$CLAUDE_DIR/$rel"
    if [ -d "$src" ]; then
        mkdir -p "$dest"
    else
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
        log "Installed $rel"
    fi
done

# --- Install plugins ---
if ! command -v claude &>/dev/null; then
    log "ERROR: 'claude' CLI not found in PATH. Skipping plugin install."
    exit 1
fi

# Register marketplaces from marketplaces.txt
if [ -f "$SCRIPT_DIR/marketplaces.txt" ]; then
    log "Registering marketplaces..."
    grep -v '^\s*#' "$SCRIPT_DIR/marketplaces.txt" | grep -v '^\s*$' | while IFS='=' read -r name repo; do
        log "  $name ($repo)"
        claude plugin marketplace add "$name" --source github --repo "$repo" 2>/dev/null || true
    done
fi

# Install plugins from plugins.txt
if [ -f "$SCRIPT_DIR/plugins.txt" ]; then
    log "Installing plugins..."
    grep -v '^\s*#' "$SCRIPT_DIR/plugins.txt" | grep -v '^\s*$' | while read -r plugin; do
        log "  $plugin"
        claude plugin install "$plugin" 2>/dev/null || log "    (already installed or failed)"
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
