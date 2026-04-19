#!/bin/sh
set -eu

if [ -n "${SPACE_ID:-}" ]; then
  DEFAULT_STATE_DIR="/data/.donkey"
  DEFAULT_CFG_PATH="/app/deploy/donkey.toml.hf"
else
  DEFAULT_STATE_DIR="/root/.donkey"
  DEFAULT_CFG_PATH="/app/deploy/donkey.toml.example"
fi

STATE_DIR="${DONKEY_STATE_DIR:-$DEFAULT_STATE_DIR}"
PADDOCKS_DIR="${DONKEY_PADDOCKS_DIR:-$STATE_DIR/paddocks}"
CFG_PATH="${DONKEY_CONFIG_PATH:-$DEFAULT_CFG_PATH}"
OWNER_UID="$(id -u)"
OWNER_GID="$(id -g)"

mkdir -p "$STATE_DIR" "$PADDOCKS_DIR"

if [ "$OWNER_UID" = "0" ] && [ -d "$STATE_DIR" ]; then
  chown -R "$OWNER_UID:$OWNER_GID" "$STATE_DIR"
fi

exec /app/donkey start --config "$CFG_PATH"
