# group_lock.sh — the grouped test runner's build lock.
#
# A lock is a directory (mkdir is atomic). Its owner writes "PID HOST" into
# it, so a waiter can tell a lock whose owner died (a run killed for memory,
# a closed terminal) from one still in use, and take the dead one over
# instead of waiting until it gives up and fails every test of the group.
# The owner line also carries the process's start time (from /proc, where
# there is one), so a PID reused by another process does not keep a dead
# lock alive. A lock without an owner (an older runner, or one being created
# this very instant) is taken over only once it is a minute old.

GROUP_LOCK_LEGACY_AGE_SEC=60

group_lock_start_time() {
  # Field 22 of /proc/PID/stat; "" where there is no /proc (macOS).
  local stat
  stat="$(cat "/proc/$1/stat" 2>/dev/null)" || { echo ""; return; }
  stat="${stat##*) }"
  set -- $stat
  echo "${20:-}"
}

group_lock_is_stale() {
  local lock="$1" pid host start now_start
  if [ -r "$lock/owner" ]; then
    read -r pid host start < "$lock/owner" || return 1
    [ -n "$pid" ] || return 1
    [ "$host" = "$(hostname)" ] || return 1   # another machine's process: cannot tell
    kill -0 "$pid" 2>/dev/null || return 0
    # Alive: the same process, unless the PID was reused since.
    now_start="$(group_lock_start_time "$pid")"
    [ -n "$start" ] && [ -n "$now_start" ] && [ "$start" != "$now_start" ] && return 0
    return 1
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
  printf '%s %s %s\n' "$BASHPID" "$(hostname)" "$(group_lock_start_time "$BASHPID")" > "$lock/owner"
}

release_group_lock() {
  rm -rf "$1"
}
