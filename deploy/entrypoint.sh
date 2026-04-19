#!/bin/sh
set -eu

STATE_DIR="${DONKEY_STATE_DIR:-/data/.donkey}"
PADDOCKS_DIR="${DONKEY_PADDOCKS_DIR:-$STATE_DIR/paddocks}"
CFG_PATH="${DONKEY_CONFIG_PATH:-/app/deploy/donkey.toml.hf}"
OWNER_UID="$(id -u)"
OWNER_GID="$(id -g)"

mkdir -p "$PADDOCKS_DIR"

if [ -d "$STATE_DIR" ]; then
  chown -R "$OWNER_UID:$OWNER_GID" "$STATE_DIR"
fi

exec /app/donkey start --config "$CFG_PATH"
