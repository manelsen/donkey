#!/usr/bin/env bash
# Donkey install script — installs as a systemd --user service (no root needed).
#
# Usage:
#   bash deploy/install.sh [--binary /path/to/donkey]
#
# After install:
#   1. Edit ~/.config/donkey/donkey.env  — fill in API keys and bot tokens
#   2. Edit ~/.config/donkey/donkey.toml — adjust config if needed (optional)
#   3. systemctl --user start donkey
#   4. systemctl --user status donkey

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BINARY_DST="$HOME/.local/bin/donkey"
CONFIG_DIR="$HOME/.config/donkey"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/donkey.service"

# ── Locate binary ─────────────────────────────────────────────────────────────

BINARY_SRC="${1:-}"
if [ -n "$BINARY_SRC" ] && [[ "$BINARY_SRC" == --binary ]]; then
  BINARY_SRC="${2:-}"
fi

if [ -z "$BINARY_SRC" ]; then
  # Try common build output locations
  for candidate in \
      "$SCRIPT_DIR/../donkey" \
      "$SCRIPT_DIR/../donkey/donkey" \
      "$(pwd)/donkey"; do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
      BINARY_SRC="$(realpath "$candidate")"
      break
    fi
  done
fi

if [ -z "$BINARY_SRC" ] || [ ! -f "$BINARY_SRC" ]; then
  echo "ERROR: Binary not found. Build it first:"
  echo "  nimble build -d:release"
  echo "Then re-run:"
  echo "  bash deploy/install.sh"
  exit 1
fi

echo "==> Installing Donkey (user service)"
echo "    Binary : $BINARY_DST"
echo "    Config : $CONFIG_DIR"
echo "    Service: $SERVICE_FILE"
echo ""

# ── Directories ───────────────────────────────────────────────────────────────

mkdir -p "$HOME/.local/bin"
mkdir -p "$CONFIG_DIR"
mkdir -p "$SERVICE_DIR"

# ── Binary ────────────────────────────────────────────────────────────────────

echo "==> Installing binary"
install -m 755 "$BINARY_SRC" "$BINARY_DST"

# ── Config files (only if they don't already exist) ──────────────────────────

if [ ! -f "$CONFIG_DIR/donkey.env" ]; then
  echo "==> Installing $CONFIG_DIR/donkey.env"
  install -m 600 "$SCRIPT_DIR/donkey.env.example" "$CONFIG_DIR/donkey.env"
  # Default data dir is already ~/.donkey via DONKEY_HOME default — no override needed
  sed -i 's|^DONKEY_HOME=.*|# DONKEY_HOME defaults to ~/.donkey — uncomment to override|' \
    "$CONFIG_DIR/donkey.env"
else
  echo "==> $CONFIG_DIR/donkey.env already exists — not overwriting"
fi

if [ ! -f "$CONFIG_DIR/donkey.toml" ]; then
  echo "==> Installing $CONFIG_DIR/donkey.toml"
  install -m 644 "$SCRIPT_DIR/donkey.toml.example" "$CONFIG_DIR/donkey.toml"
else
  echo "==> $CONFIG_DIR/donkey.toml already exists — not overwriting"
fi

# ── Systemd user service ──────────────────────────────────────────────────────

echo "==> Installing systemd user service"
install -m 644 "$SCRIPT_DIR/donkey.service" "$SERVICE_FILE"
systemctl --user daemon-reload
systemctl --user enable donkey

# ── PATH hint ─────────────────────────────────────────────────────────────────

if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo ""
  echo "NOTE: $HOME/.local/bin is not in your PATH."
  echo "Add to ~/.bashrc or ~/.zshrc:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "✓ Donkey installed."
echo ""
echo "Next steps:"
echo "  1. Fill in API keys and bot tokens:"
echo "       \$EDITOR $CONFIG_DIR/donkey.env"
echo "  2. (Optional) adjust config:"
echo "       \$EDITOR $CONFIG_DIR/donkey.toml"
echo "  3. Start the service:"
echo "       systemctl --user start donkey"
echo "  4. Check status and logs:"
echo "       systemctl --user status donkey"
echo "       journalctl --user -u donkey -f"
echo ""
echo "To start automatically at boot (without login):"
echo "  loginctl enable-linger $USER"
