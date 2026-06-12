#!/usr/bin/env bash
set -euo pipefail

log() { printf '[install] %s\n' "$1"; }

if [ "$EUID" -eq 0 ]; then
    log "ERROR: Run as your normal user — sudo will be invoked where needed."
    exit 1
fi

if ! command -v sudo &>/dev/null; then
    log "ERROR: 'sudo' not found in PATH."
    exit 1
fi

# --- System runtime libraries for Chrome for Testing (Arch / pacman) ---
if ! command -v pacman &>/dev/null; then
    log "ERROR: 'pacman' not found. This script targets Arch-based systems."
    exit 1
fi

DEPS=(
    nodejs
    npm
    nss
    nspr
    libxkbcommon
    atk
    at-spi2-atk
    at-spi2-core
    libxcomposite
    libxdamage
    libxrandr
    libxcursor
    libxi
    libxtst
    libdrm
    mesa
    cups
    alsa-lib
    pango
    cairo
    gtk3
    dbus
)

log "Installing npm + Chrome runtime libraries via pacman..."
# --noconfirm: this is an unattended admin script; user already opted in by running it.
sudo pacman -S --needed --noconfirm "${DEPS[@]}"

# --- Install agent-browser CLI ---
if ! command -v npm &>/dev/null; then
    log "WARNING: 'npm' not found in PATH. Skipping agent-browser install."
else
    if ! command -v agent-browser &>/dev/null; then
        log "Installing agent-browser via npm..."
        sudo npm i -g agent-browser
        hash -r
        if ! command -v agent-browser &>/dev/null; then
            log "ERROR: agent-browser installed but not on PATH. Check 'npm root -g' prefix."
            exit 1
        fi
    else
        log "agent-browser CLI already installed"
    fi
    # `agent-browser install` fetches Chrome for Testing; idempotent on subsequent runs.
    log "Ensuring Chrome for Testing is set up..."
    agent-browser install
fi

log "Done!"
