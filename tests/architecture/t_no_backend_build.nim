## The project must still type-check without a graph backend: the Markdown
## store is a supported mode, and the default test run never builds it.

import std/[os, osproc, strutils, unittest]

suite "build without a graph backend":

  test "the daemon type-checks with SQLite and PostgreSQL disabled":
    let root = currentSourcePath().parentDir.parentDir.parentDir
    let (output, code) = execCmdEx(
      "nim check --hints:off -u:withSqlite -u:withPostgres " &
      quoteShell(root / "src" / "donkey.nim"),
      workingDir = root)
    if code != 0:
      for line in output.splitLines():
        if "Error" in line:
          checkpoint(line)
    check code == 0
