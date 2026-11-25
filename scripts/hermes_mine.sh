#!/usr/bin/env bash
## hermes_mine.sh — reproducible extraction of hermes-agent fix commits.
##
## Usage: bash scripts/hermes_mine.sh <component> [--since <hash>]
##
## The hermes repository is read-only for this script: only `git log`,
## `git show` and `git cat-file` are used. Output is deterministic, so two runs
## over the same ref produce byte-identical files.
set -euo pipefail

cd "$(dirname "$0")/.."

HERMES_DIR="${HERMES_DIR:-/home/micelio/git/hermes-agent}"
HERMES_REF="${HERMES_REF:-b3746e35dd}"

usage() {
  echo "usage: $0 <component> [--since <hash>]" >&2
  echo "supported components: telegram, discord, whatsapp" >&2
}

component="${1:-}"
if [ -z "$component" ]; then
  usage
  exit 2
fi
shift

since=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since)
      if [ $# -lt 2 ]; then
        usage
        exit 2
      fi
      since="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [ ! -d "$HERMES_DIR" ]; then
  echo "hermes directory not found: $HERMES_DIR" >&2
  exit 1
fi
if [ "$(git -C "$HERMES_DIR" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  echo "hermes repository is shallow: run 'git fetch --unshallow' there first" >&2
  exit 1
fi

## Resolve once: ranges and LAST_SYNC always use the full commit id.
resolved_ref="$(git -C "$HERMES_DIR" rev-parse --verify "$HERMES_REF^{commit}" 2>/dev/null)" || {
  echo "hermes ref not found: $HERMES_REF" >&2
  exit 1
}

range="$resolved_ref"
if [ -n "$since" ]; then
  resolved_since="$(git -C "$HERMES_DIR" rev-parse --verify "$since^{commit}" 2>/dev/null)" || {
    echo "since ref not found: $since" >&2
    exit 1
  }
  range="$resolved_since..$resolved_ref"
fi

## One `case` block per component: the grep patterns and the paths that scope
## the fix commits. Adding a component means adding a branch here.
case "$component" in
  telegram)
    out_dir="docs/hermes-mining/telegram"
    hashes="$(
      {
        git -C "$HERMES_DIR" log "$range" --no-merges -i -E \
          --grep='^fix.*telegram' --format='%H'
        git -C "$HERMES_DIR" log "$range" --no-merges -i -E \
          --grep='^fix' --format='%H' -- plugins/platforms/telegram
      } | sort -u
    )"
    ;;
  discord)
    out_dir="docs/hermes-mining/discord"
    hashes="$(
      {
        git -C "$HERMES_DIR" log "$range" --no-merges -i -E \
          --grep='^fix.*discord' --format='%H'
        git -C "$HERMES_DIR" log "$range" --no-merges -i -E \
          --grep='^fix' --format='%H' -- \
            plugins/platforms/discord \
            gateway/platforms/discord.py
      } | sort -u
    )"
    ;;
  whatsapp)
    ## Donkey speaks the Cloud API; hermes has it (plugins/platforms/
    ## whatsapp_cloud) beside a bridge-based adapter. Both are extracted;
    ## classification marks bridge-only cases as not applicable.
    out_dir="docs/hermes-mining/whatsapp"
    hashes="$(
      {
        git -C "$HERMES_DIR" log "$range" --no-merges -i -E \
          --grep='^fix.*whatsapp' --format='%H'
        git -C "$HERMES_DIR" log "$range" --no-merges -i -E \
          --grep='^fix' --format='%H' -- \
            plugins/platforms/whatsapp_cloud \
            plugins/platforms/whatsapp \
            gateway/platforms/whatsapp_common.py
      } | sort -u
    )"
    ;;
  *)
    echo "unknown component: $component" >&2
    echo "supported components: telegram, discord, whatsapp" >&2
    exit 2
    ;;
esac

mkdir -p "$out_dir"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

{
  printf 'hash\tdate\tsubject\tfiles_changed\ttest_files\n'
  while IFS= read -r hash; do
    [ -n "$hash" ] || continue
    git -C "$HERMES_DIR" show --no-renames \
      --pretty=format:'%H%x09%cs%x09%s' --name-only "$hash" |
      awk -F'\t' -v OFS='\t' '
        NR == 1 {
          short = substr($1, 1, 10)
          date = $2
          subject = $3
          gsub(/\t/, " ", subject)
          next
        }
        $0 == "" { next }
        {
          files++
          if ($0 ~ /^tests\/.*test_[^\/]*\.py$/) {
            tests = (tests == "" ? $0 : tests ";" $0)
          }
        }
        END {
          print short, date, subject, files + 0, (tests == "" ? "-" : tests)
        }
      '
  done <<< "$hashes"
} > "$tmp"

## Header first, then chronological order with the hash as a stable tie-break.
{
  head -n 1 "$tmp"
  tail -n +2 "$tmp" | sort -t$'\t' -k2,2 -k1,1
} > "$out_dir/commits.tsv"

printf '%s\n' "$resolved_ref" > "$out_dir/LAST_SYNC"

lines=$(($(wc -l < "$out_dir/commits.tsv") - 1))
echo "extracted $lines commits for $component into $out_dir/commits.tsv"
