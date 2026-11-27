# group_lock.sh — the grouped test runner's build lock.
#
# A lock is a directory (mkdir is atomic). Its owner writes "PID HOST" into
# it, so a waiter can tell a lock whose owner died (a run killed for memory,
# a closed terminal) from one still in use, and take the dead one over
# instead of waiting until it gives up and fails every test of the group.
# A lock without an owner (an older runner, or one being created this very
# instant) is taken over only once it is a minute old.

GROUP_LOCK_LEGACY_AGE_SEC=60

group_lock_is_stale() {
  local lock="$1" pid host
  if [ -r "$lock/owner" ]; then
    read -r pid host < "$lock/owner" || return 1
    [ -n "$pid" ] || return 1
    [ "$host" = "$(hostname)" ] || return 1   # another machine's process: cannot tell
    kill -0 "$pid" 2>/dev/null && return 1
    return 0
  fi
  local made now
  made="$(stat -c %Y "$lock" 2>/dev/null)" || return 1
  now="$(date +%s)"
  [ $((now - made)) -gt "$GROUP_LOCK_LEGACY_AGE_SEC" ]
}

reclaim_group_lock() {
  # Moves the stale lock aside first: of several waiters, one wins the move.
  # If what it moved turns out to be alive (replaced in between), it goes back.
  local lock="$1" grave="$1.reclaim.$BASHPID"
  mv "$lock" "$grave" 2>/dev/null || return 0
  if group_lock_is_stale "$grave"; then
    echo "Reclaiming stale group build lock: $lock" >&2
    rm -rf "$grave"
  else
    mv "$grave" "$lock" 2>/dev/null || true
  fi
}

acquire_group_lock() {
  local lock="$1" max="${2:-600}" tries=0
  while ! mkdir "$lock" 2>/dev/null; do
    if group_lock_is_stale "$lock"; then
      reclaim_group_lock "$lock"
      continue
    fi
    tries=$((tries + 1))
    if [ "$tries" -gt "$max" ]; then
      echo "Timed out waiting for group build lock: $lock" >&2
      return 1
    fi
    sleep 0.2
  done
  printf '%s %s\n' "$BASHPID" "$(hostname)" > "$lock/owner"
}

release_group_lock() {
  rm -rf "$1"
}
