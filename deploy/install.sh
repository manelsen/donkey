#!/usr/bin/env bash
# Install script — installs as a systemd --user service (no root needed).
#
# Usage:
#   bash deploy/install.sh [--binary /path/to/binary]
#
# After install:
#   1. Edit ~/.config/$CONFIG_DIR/$ENV_FILE  — fill in API keys and bot tokens
#   2. Edit ~/.config/$CONFIG_DIR/$CONFIG_FILE — adjust config if needed (optional)
#   3. systemctl --user start $APP_SLUG
#   4. systemctl --user status $APP_SLUG

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_NAME="${APP_NAME:-Donkey}"
APP_SLUG="${APP_SLUG:-donkey}"
CONFIG_DIR_NAME="${CONFIG_DIR_NAME:-$APP_SLUG}"
CONFIG_FILE="${CONFIG_FILE:-$APP_SLUG.toml}"
ENV_FILE="${ENV_FILE:-$APP_SLUG.env}"
SERVICE_UNIT="${SERVICE_UNIT:-$APP_SLUG.service}"
APP_REPO_URL="${APP_REPO_URL:-https://github.com/manelsen/donkey}"
CONFIG_SECTION_NAME="${CONFIG_SECTION_NAME:-$APP_SLUG}"
HOME_DIR_NAME="${HOME_DIR_NAME:-.$APP_SLUG}"

BINARY_DST="$HOME/.local/bin/$APP_SLUG"
CONFIG_DIR="$HOME/.config/$CONFIG_DIR_NAME"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/$SERVICE_UNIT"
ENV_TEMPLATE="$SCRIPT_DIR/app.env.example.template"
CONFIG_TEMPLATE="$SCRIPT_DIR/app.toml.example.template"
SERVICE_TEMPLATE="$SCRIPT_DIR/app.service.template"

render_template() {
  local src="$1"
  local dst="$2"
  sed \
    -e "s|__APP_NAME__|$APP_NAME|g" \
    -e "s|__APP_SLUG__|$APP_SLUG|g" \
    -e "s|__CONFIG_DIR_NAME__|$CONFIG_DIR_NAME|g" \
    -e "s|__CONFIG_FILE_NAME__|$CONFIG_FILE|g" \
    -e "s|__ENV_FILE_NAME__|$ENV_FILE|g" \
    -e "s|__CONFIG_SECTION_NAME__|$CONFIG_SECTION_NAME|g" \
    -e "s|__APP_REPO_URL__|$APP_REPO_URL|g" \
    -e "s|__HOME_DIR_NAME__|$HOME_DIR_NAME|g" \
    "$src" > "$dst"
}

# ── Locate binary ─────────────────────────────────────────────────────────────

BINARY_SRC="${1:-}"
if [ -n "$BINARY_SRC" ] && [[ "$BINARY_SRC" == --binary ]]; then
  BINARY_SRC="${2:-}"
fi

if [ -z "$BINARY_SRC" ]; then
  # Try common build output locations
  for candidate in \
      "$SCRIPT_DIR/../$APP_SLUG" \
      "$SCRIPT_DIR/../$APP_SLUG/$APP_SLUG" \
      "$(pwd)/$APP_SLUG"; do
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

echo "==> Installing $APP_NAME (user service)"
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

if [ ! -f "$CONFIG_DIR/$ENV_FILE" ]; then
  echo "==> Installing $CONFIG_DIR/$ENV_FILE"
  render_template "$ENV_TEMPLATE" "$CONFIG_DIR/$ENV_FILE"
  chmod 600 "$CONFIG_DIR/$ENV_FILE"
  # Default data dir is already ~/$HOME_DIR_NAME via DONKEY_HOME default — no override needed
  sed -i "s|^DONKEY_HOME=.*|# DONKEY_HOME defaults to ~/$HOME_DIR_NAME — uncomment to override|" \
    "$CONFIG_DIR/$ENV_FILE"
else
  echo "==> $CONFIG_DIR/$ENV_FILE already exists — not overwriting"
fi

if [ ! -f "$CONFIG_DIR/$CONFIG_FILE" ]; then
  echo "==> Installing $CONFIG_DIR/$CONFIG_FILE"
  render_template "$CONFIG_TEMPLATE" "$CONFIG_DIR/$CONFIG_FILE"
  chmod 644 "$CONFIG_DIR/$CONFIG_FILE"
else
  echo "==> $CONFIG_DIR/$CONFIG_FILE already exists — not overwriting"
fi

# ── Systemd user service ──────────────────────────────────────────────────────

echo "==> Installing systemd user service"
render_template "$SERVICE_TEMPLATE" "$SERVICE_FILE"
chmod 644 "$SERVICE_FILE"
systemctl --user daemon-reload
systemctl --user enable "$APP_SLUG"

# ── PATH hint ─────────────────────────────────────────────────────────────────

if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo ""
  echo "NOTE: $HOME/.local/bin is not in your PATH."
  echo "Add to ~/.bashrc or ~/.zshrc:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "✓ $APP_NAME installed."
echo ""
echo "Next steps:"
echo "  1. Fill in API keys and bot tokens:"
echo "       \$EDITOR $CONFIG_DIR/$ENV_FILE"
echo "  2. (Optional) adjust config:"
echo "       \$EDITOR $CONFIG_DIR/$CONFIG_FILE"
echo "  3. Start the service:"
echo "       systemctl --user start $APP_SLUG"
echo "  4. Check status and logs:"
echo "       systemctl --user status $APP_SLUG"
echo "       journalctl --user -u $APP_SLUG -f"
echo ""
echo "To start automatically at boot (without login):"
echo "  loginctl enable-linger $USER"
