#!/usr/bin/env bash
set -euo pipefail

version="${1:-v0.1.9}"

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Linux) platform_os="linux" ;;
  Darwin) platform_os="macos" ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT) platform_os="windows" ;;
  *)
    echo "unsupported OS: $os" >&2
    exit 1
    ;;
esac

case "$arch" in
  x86_64|amd64) platform_arch="x86_64" ;;
  aarch64|arm64) platform_arch="aarch64" ;;
  *)
    echo "unsupported architecture: $arch" >&2
    exit 1
    ;;
esac

asset="sqlite-vec-${version#v}-loadable-${platform_os}-${platform_arch}.tar.gz"
url="https://github.com/asg017/sqlite-vec/releases/download/${version}/${asset}"
target_dir="vendor/sqlite-vec/${platform_os}-${platform_arch}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$target_dir"
curl -sS -L "$url" -o "$tmp_dir/sqlite-vec.tar.gz"
tar -xzf "$tmp_dir/sqlite-vec.tar.gz" -C "$target_dir"

echo "vendored sqlite-vec to $target_dir"
