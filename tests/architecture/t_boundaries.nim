import std/[osproc, unittest]

suite "boundary enforcement":
  test "layer import rules stay intact":
    check execCmd("bash scripts/check_boundaries.sh") == 0
