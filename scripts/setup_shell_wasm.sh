#!/usr/bin/env bash
# scripts/setup_shell_wasm.sh — Build go-busybox WASM for Donkey sandbox.
#
# Prerequisites: Go 1.22+, TinyGo 0.34+ (auto-installed if missing)
# Output: ~/.donkey/shell.wasm (~2MB, 57 applets including ash, cat, grep, sed, awk)
#
# Usage:
#   scripts/setup_shell_wasm.sh          # build from source
#   scripts/setup_shell_wasm.sh --clean  # clean and rebuild

set -euo pipefail

DONKEY_HOME="${DONKEY_HOME:-$HOME/.donkey}"
# Must be named "busybox" (no .wasm extension) so argv[0] works with
# the go-busybox multi-call dispatcher.
SHELL_WASM="$DONKEY_HOME/busybox"
BUILD_DIR="/tmp/go-busybox-build"
TINYGO_VERSION="0.38.0"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# ── Check prerequisites ─────────────────────────────────────────────────────

check_go() {
    if ! command -v go &>/dev/null; then
        error "Go not found. Install from https://go.dev/dl/"
    fi
    local go_version
    go_version=$(go version | grep -oP 'go\K[0-9]+\.[0-9]+')
    info "Go $go_version found"
}

install_tinygo() {
    if command -v tinygo &>/dev/null; then
        info "TinyGo $(tinygo --version 2>&1 | head -1) found"
        return
    fi

    warn "TinyGo not found. Installing v${TINYGO_VERSION}..."
    local url="https://github.com/tinygo-org/tinygo/releases/download/v${TINYGO_VERSION}/tinygo${TINYGO_VERSION}.linux-amd64.tar.gz"
    local tmpdir="/tmp/tinygo-install-$$"
    mkdir -p "$tmpdir"
    wget -q "$url" -O "$tmpdir/tinygo.tar.gz"
    tar -xzf "$tmpdir/tinygo.tar.gz" -C "$tmpdir"

    # Install to /usr/local (requires sudo) or ~/.local
    if [[ -w /usr/local/bin ]]; then
        cp "$tmpdir/tinygo/bin/tinygo" /usr/local/bin/
        info "TinyGo installed to /usr/local/bin/tinygo"
    else
        mkdir -p "$HOME/.local/bin"
        cp "$tmpdir/tinygo/bin/tinygo" "$HOME/.local/bin/"
        export PATH="$HOME/.local/bin:$PATH"
        info "TinyGo installed to ~/.local/bin/tinygo"
    fi
    rm -rf "$tmpdir"
}

# ── Build go-busybox ─────────────────────────────────────────────────────────

build_shell_wasm() {
    mkdir -p "$DONKEY_HOME"

    if [[ -f "$SHELL_WASM" && "${1:-}" != "--clean" ]]; then
        info "busybox already exists at $SHELL_WASM"
        info "Use --clean to rebuild"
        return
    fi

    info "Cloning go-busybox..."
    rm -rf "$BUILD_DIR"
    git clone --depth 1 https://github.com/rcarmo/go-busybox "$BUILD_DIR"

    # Patch go.mod for TinyGo compatibility
    cd "$BUILD_DIR"
    local go_version
    go_version=$(go version | grep -oP 'go\K[0-9]+\.[0-9]+\.[0-9]+')
    sed -i "s/^go .*/go ${go_version}/" go.mod

    # Patch ls applet for WASI compatibility
    if [[ ! -f pkg/applets/ls/ls_unix.go ]]; then
        info "Patching ls applet for WASI..."
        # Create platform-specific getBlocks
        cat > pkg/applets/ls/ls_unix.go << 'GOEOF'
//go:build !wasip1

package ls

import (
	"io/fs"
	"syscall"
)

func getBlocks(path string, info fs.FileInfo) int64 {
	if sys := info.Sys(); sys != nil {
		if stat, ok := sys.(*syscall.Stat_t); ok {
			return stat.Blocks / 2
		}
	}
	return (info.Size() + 4095) / 4096 * 4
}
GOEOF

        cat > pkg/applets/ls/ls_wasip1.go << 'GOEOF'
//go:build wasip1

package ls

import (
	"io/fs"
	"syscall"
)

func getBlocks(path string, info fs.FileInfo) int64 {
	if sys := info.Sys(); sys != nil {
		if stat, ok := sys.(*syscall.Stat_t); ok {
			return int64((stat.Size + 511) / 512)
		}
	}
	return 0
}
GOEOF

        # Remove inline getBlocks from ls.go
        sed -i '/^func getBlocks/,/^}$/d' pkg/applets/ls/ls.go
    fi

    info "Building shell.wasm with TinyGo..."
    tinygo build -target=wasip1 -opt=z -no-debug -o busybox.wasm ./cmd/busybox

    cp busybox.wasm "$SHELL_WASM"
    local size
    size=$(du -h "$SHELL_WASM" | cut -f1)
    info "Built busybox ($size) → $SHELL_WASM"

    # Cleanup
    cd /
    rm -rf "$BUILD_DIR"
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    echo -e "${GREEN}Donkey shell.wasm setup${NC}"
    echo "Building go-busybox WASM for sandbox execution..."
    echo

    check_go
    install_tinygo
    build_shell_wasm "$@"

    echo
    info "Done! Test with:"
    echo "  wasmtime --dir=/tmp $SHELL_WASM echo 'hello from wasm'"
}

main "$@"
