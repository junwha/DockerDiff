#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC_PATH="${HOME}/.bashrc"
PATH_EXPORT="export PATH=${SCRIPT_DIR}:\$PATH"

if ! grep -Fqx "$PATH_EXPORT" "$BASHRC_PATH" 2>/dev/null; then
    echo "$PATH_EXPORT" >> "$BASHRC_PATH"
    echo "[ddiff] Added ${SCRIPT_DIR} to PATH in ${BASHRC_PATH}."
else
    echo "[ddiff] PATH entry already exists in ${BASHRC_PATH}."
fi

if command -v podman >/dev/null 2>&1 && ! command -v skopeo >/dev/null 2>&1; then
    echo "[ddiff] podman detected but skopeo is missing. Installing skopeo..."

    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y skopeo
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y skopeo
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y skopeo
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm skopeo
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper --non-interactive install skopeo
    elif command -v brew >/dev/null 2>&1; then
        brew install skopeo
    else
        echo "[ddiff] Could not detect a supported package manager."
        echo "[ddiff] Please install skopeo manually."
        exit 1
    fi

    echo "[ddiff] skopeo installation complete."
fi

echo "[ddiff] Installation complete. Run: source ~/.bashrc"
