#!/bin/bash
# Generate HTML documentation for the Donkey project
# Usage: ./scripts/generate_docs.sh [--serve]
#
# --serve: Start a local HTTP server to view the docs
#
# Requirements: Nim compiler with docgen support

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTDIR="${PROJECT_ROOT}/htmldocs"

cd "$PROJECT_ROOT"

echo "==> Generating Donkey documentation..."
echo "    Source: src/"
echo "    Output: $OUTDIR/"

# Clean previous output
rm -rf "$OUTDIR"

# Generate HTML documentation for the entire project
# --project: process all imported modules
# --index:on: generate index.html with search
# --outdir: output directory
nim doc \
  --project \
  --index:on \
  --outdir:"$OUTDIR" \
  --git.url:https://github.com/donkey-ai/donkey \
  --git.commit:main \
  src/donkey.nim

echo ""
echo "==> Documentation generated successfully!"
echo "    Open: $OUTDIR/donkey.html"
echo ""

if [ "$1" = "--serve" ]; then
  echo "==> Starting HTTP server on http://localhost:8080"
  echo "    Press Ctrl+C to stop"
  python3 -m http.server 8080 --directory "$OUTDIR"
fi
