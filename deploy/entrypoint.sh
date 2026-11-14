#!/bin/sh
set -eu

SPACE_HINT="${SPACE_ID:-}${SPACE_HOST:-}${SPACE_REPO_NAME:-}${SPACE_AUTHOR_NAME:-}"

if [ -n "$SPACE_HINT" ] || [ -d /data ]; then
  DEFAULT_STATE_DIR="/data/.donkey"
  # Hugging Face Spaces health-checks the public app port. Keep the gateway on
  # 0.0.0.0 and require a token for data endpoints; generate one when the Space
  # does not provide it so the probe can reach the public /health route.
  export DONKEY_HTTP_BIND="${DONKEY_HTTP_BIND:-0.0.0.0}"
  export DONKEY_HTTP_ALLOW_INSECURE="${DONKEY_HTTP_ALLOW_INSECURE:-1}"
  if [ -z "${DONKEY_HTTP_TOKEN:-}" ]; then
    if command -v openssl >/dev/null 2>&1; then
      DONKEY_HTTP_TOKEN="$(openssl rand -hex 16)"
    else
      DONKEY_HTTP_TOKEN="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    fi
    export DONKEY_HTTP_TOKEN
    echo "donkey entrypoint: generated DONKEY_HTTP_TOKEN=$DONKEY_HTTP_TOKEN" >&2
  fi
else
  DEFAULT_STATE_DIR="/root/.donkey"
fi

if [ -n "${DONKEY_CONFIG_PATH:-}" ]; then
  CFG_PATH="$DONKEY_CONFIG_PATH"
elif [ "$DEFAULT_STATE_DIR" = "/data/.donkey" ]; then
  CFG_PATH="/app/deploy/donkey.toml.hf"
else
  CFG_PATH="/app/deploy/donkey.toml.container"
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
exec /app/donkey "--config=$CFG_PATH" start
