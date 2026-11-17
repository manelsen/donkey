#!/usr/bin/env bash
# Update script — replaces the installed binary with the one CI built from
# master, so the server does not have to compile anything.
#
# Usage:
#   bash deploy/update.sh            # download, verify, install, restart
#   bash deploy/update.sh --rollback # put the previous binary back
#
# The binary comes from the rolling "nightly" pre-release of the repository.
# It is built against glibc 2.28 and runs on x86_64 Linux only.

set -euo pipefail

APP_SLUG="${APP_SLUG:-donkey}"
APP_REPO_URL="${APP_REPO_URL:-https://github.com/manelsen/donkey}"
RELEASE_TAG="${RELEASE_TAG:-nightly}"
ASSET="${APP_SLUG}-linux-x86_64.tar.gz"
BINARY_DST="${BINARY_DST:-$HOME/.local/bin/$APP_SLUG}"
BINARY_PREV="$BINARY_DST.prev"

restart_service() {
  if systemctl --user is-active --quiet "$APP_SLUG" 2>/dev/null; then
    echo "==> Restarting $APP_SLUG"
    systemctl --user restart "$APP_SLUG"
  else
    echo "==> Service $APP_SLUG is not running; start it with: systemctl --user start $APP_SLUG"
  fi
}

if [ "${1:-}" = "--rollback" ]; then
  if [ ! -f "$BINARY_PREV" ]; then
    echo "ERROR: no previous binary at $BINARY_PREV"
    exit 1
  fi
  install -m 755 "$BINARY_PREV" "$BINARY_DST"
  echo "==> Restored $("$BINARY_DST" --version)"
  restart_service
  exit 0
fi

if [ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]; then
  echo "ERROR: the published binary is for x86_64 Linux; this is $(uname -s)-$(uname -m)."
  echo "Build from source instead: nimble build -d:release"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

BASE_URL="$APP_REPO_URL/releases/download/$RELEASE_TAG"
echo "==> Downloading $ASSET ($RELEASE_TAG)"
curl -fsSL --retry 3 "$BASE_URL/$ASSET" -o "$WORK_DIR/$ASSET"
curl -fsSL --retry 3 "$BASE_URL/$ASSET.sha256" -o "$WORK_DIR/$ASSET.sha256"

echo "==> Verifying checksum"
(cd "$WORK_DIR" && sha256sum -c "$ASSET.sha256")

tar -xzf "$WORK_DIR/$ASSET" -C "$WORK_DIR"
NEW_BINARY="$WORK_DIR/$APP_SLUG"

# Run it once before touching the installed one: a binary that cannot start
# on this machine must not replace one that can.
NEW_VERSION="$("$NEW_BINARY" --version)"
echo "==> Downloaded $NEW_VERSION"

mkdir -p "$(dirname "$BINARY_DST")"
if [ -f "$BINARY_DST" ]; then
  cp -p "$BINARY_DST" "$BINARY_PREV"
  echo "==> Previous binary kept at $BINARY_PREV"
fi
install -m 755 "$NEW_BINARY" "$BINARY_DST"
echo "==> Installed $BINARY_DST"

restart_service
