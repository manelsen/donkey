#!/usr/bin/env bash
# Install script — installs as a systemd --user service (no root needed).
#
# Usage:
#   bash deploy/install.sh [--binary /path/to/binary] [--lightpanda]
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

# Lightpanda is installed on the service host, where the daemon starts it.
install_lightpanda() (
  local version=1.0.4 arch checksum asset work_dir
  arch="$(uname -m)"
  case "$(uname -s)-$arch" in
    Linux-x86_64) checksum=7d22651129901203abdb95c64f49069c49e88f5211f4d8c4c6828c123c4adab4 ;;
    Linux-aarch64) checksum=f021d49a0b66d07bf2633f8e00870b9075293516f872695b0ca4aeb5848b6ea8 ;;
    *) echo "ERROR: --lightpanda requires Linux x86_64 or aarch64." >&2; exit 1 ;;
  esac

  if [ -x "$LIGHTPANDA_DST" ] &&
      printf '%s  %s\n' "$checksum" "$LIGHTPANDA_DST" | sha256sum --status -c; then
    "$LIGHTPANDA_DST" version >/dev/null
    return 0
  fi

  work_dir="$(mktemp -d "$(dirname "$LIGHTPANDA_DST")/.lightpanda.XXXXXX")"
  trap 'rm -rf "$work_dir"' EXIT
  asset="lightpanda-$arch-linux"
  echo "==> Downloading Lightpanda $version"
  curl -fsSL --retry 3 \
    "https://github.com/lightpanda-io/browser/releases/download/$version/$asset" \
    -o "$work_dir/lightpanda"
  printf '%s  %s\n' "$checksum" "$work_dir/lightpanda" | sha256sum -c
  chmod 755 "$work_dir/lightpanda"
  "$work_dir/lightpanda" version
  mv -fT "$work_dir/lightpanda" "$LIGHTPANDA_DST"
)

configure_lightpanda() (
  local env_file temp_env
  env_file="$(realpath "$CONFIG_DIR/$ENV_FILE")"
  temp_env="$(mktemp "${env_file}.XXXXXX")"
  trap 'rm -f "$temp_env"' EXIT
  awk '!/^[[:space:]]*DONKEY_BROWSER_(BACKEND|PATH)[[:space:]]*=/' "$env_file" > "$temp_env"
  printf 'DONKEY_BROWSER_BACKEND=lightpanda\nDONKEY_BROWSER_PATH="%s"\n' \
    "$LIGHTPANDA_DST" >> "$temp_env"
  mv -f "$temp_env" "$env_file"
)

# ── Locate binary ─────────────────────────────────────────────────────────────

BINARY_SRC=""
WITH_LIGHTPANDA=false
LIGHTPANDA_DST="$HOME/.local/bin/lightpanda"
usage() {
  echo "Usage: bash deploy/install.sh [--binary /path/to/binary] [--lightpanda]"
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --binary)
      if [ "$#" -lt 2 ] || [[ "$2" == --* ]]; then
        usage >&2
        exit 2
      fi
      BINARY_SRC="$2"
      shift ;;
    --lightpanda) WITH_LIGHTPANDA=true ;;
    -h|--help) usage; exit 0 ;;
    -*)
      usage >&2
      exit 2 ;;
    *)
      if [ -n "$BINARY_SRC" ]; then
        usage >&2
        exit 2
      fi
      BINARY_SRC="$1" ;;
  esac
  shift
done

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

if "$WITH_LIGHTPANDA"; then
  if [ -n "${DONKEY_BROWSER_PROXY:-}" ] ||
      { [ -f "$CONFIG_DIR/$ENV_FILE" ] && awk '
        /^[[:space:]]*DONKEY_BROWSER_PROXY[[:space:]]*=/ {
          sub(/^[^=]*=[[:space:]]*/, "")
          sub(/[[:space:]]*$/, "")
          configured = ($0 != "" && $0 != "\"\"" && $0 != "\047\047")
        }
        END { exit !configured }
      ' "$CONFIG_DIR/$ENV_FILE"; }; then
    echo "ERROR: --lightpanda is incompatible with DONKEY_BROWSER_PROXY." >&2
    exit 1
  fi
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

if "$WITH_LIGHTPANDA"; then
  install_lightpanda
fi

# ── Binary ────────────────────────────────────────────────────────────────────

if ! [ "$BINARY_SRC" -ef "$BINARY_DST" ]; then
  echo "==> Installing binary"
  install -m 755 "$BINARY_SRC" "$BINARY_DST"
fi

# ── Config files (only if they don't already exist) ──────────────────────────

if [ ! -f "$CONFIG_DIR/$ENV_FILE" ]; then
  echo "==> Installing $CONFIG_DIR/$ENV_FILE"
  render_template "$ENV_TEMPLATE" "$CONFIG_DIR/$ENV_FILE"
  chmod 600 "$CONFIG_DIR/$ENV_FILE"
  # Default data dir is already ~/$HOME_DIR_NAME via DONKEY_HOME default — no override needed
  sed -i "s|^DONKEY_HOME=.*|# DONKEY_HOME defaults to ~/$HOME_DIR_NAME — uncomment to override|" \
    "$CONFIG_DIR/$ENV_FILE"
else
  echo "==> Keeping existing $CONFIG_DIR/$ENV_FILE"
fi

if "$WITH_LIGHTPANDA"; then
  configure_lightpanda
  echo "==> Enabled Lightpanda in $CONFIG_DIR/$ENV_FILE"
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
