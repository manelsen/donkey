#!/bin/sh
set -eu

SPACE_HINT="${SPACE_ID:-}${SPACE_HOST:-}${SPACE_REPO_NAME:-}${SPACE_AUTHOR_NAME:-}"

if [ -n "$SPACE_HINT" ] || [ -d /data ]; then
  DEFAULT_STATE_DIR="/data/.donkey"
else
  DEFAULT_STATE_DIR="/root/.donkey"
fi

if [ -n "${DONKEY_CONFIG_PATH:-}" ]; then
  CFG_PATH="$DONKEY_CONFIG_PATH"
elif [ "$DEFAULT_STATE_DIR" = "/data/.donkey" ]; then
  CFG_PATH="/app/deploy/donkey.toml.hf"
else
  CFG_PATH="/app/deploy/donkey.toml.example"
fi

STATE_DIR="${DONKEY_STATE_DIR:-$DEFAULT_STATE_DIR}"
PADDOCKS_DIR="${DONKEY_PADDOCKS_DIR:-$STATE_DIR/paddocks}"
OWNER_UID="$(id -u)"
OWNER_GID="$(id -g)"

mkdir -p "$STATE_DIR" "$PADDOCKS_DIR"

if [ "$OWNER_UID" = "0" ] && [ -d "$STATE_DIR" ]; then
  chown -R "$OWNER_UID:$OWNER_GID" "$STATE_DIR"
fi

if [ ! -f "$CFG_PATH" ]; then
  echo "donkey entrypoint: config not found: $CFG_PATH" >&2
  exit 1
fi

echo "donkey entrypoint: config=$CFG_PATH state=$STATE_DIR"
exec /app/donkey --config "$CFG_PATH" start
