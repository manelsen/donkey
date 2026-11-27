## The grouped test runner's build lock (scripts/lib/group_lock.sh): a lock
## whose owner died (a run killed for memory, say) is taken over instead of
## waited on until the run gives up and fails every test of the group.

import std/[os, osproc, strutils, unittest]

const Root = currentSourcePath().parentDir.parentDir.parentDir
const Lib = Root / "scripts" / "lib" / "group_lock.sh"

proc sh(script: string): tuple[output: string, exitCode: int] =
  execCmdEx("bash -c " & quoteShell("source " & quoteShell(Lib) & "\n" & script))

proc freshLock(tag: string): string =
  result = getTempDir() / ("donkey_group_lock_" & tag)
  removeDir(result)
  removeDir(result & ".lock")
  result = result & ".lock"

proc runTests*() =
  suite "group build lock":
    test "the owner is written: this process and this host":
      let lock = freshLock("owner")
      let r = sh("acquire_group_lock " & quoteShell(lock) & " 3 && echo $BASHPID && cat " &
                 quoteShell(lock / "owner"))
      check r.exitCode == 0
      let lines = r.output.strip.splitLines
      let fields = lines[1].split(' ')
      check fields.len == 3 and fields[0] == lines[0] and fields[1] == execCmdEx("hostname").output.strip
      check fields[2].len > 0 and fields[2].allCharsInSet(Digits)

    test "a lock whose owner is dead is taken over":
      let lock = freshLock("dead")
      createDir(lock)
      let dead = execCmdEx("bash -c 'echo $$'").output.strip   ## a process that is gone
      writeFile(lock / "owner", dead & " " & execCmdEx("hostname").output.strip & "\n")
      let r = sh("acquire_group_lock " & quoteShell(lock) & " 3 && echo got")
      check r.exitCode == 0 and "got" in r.output
      check "Reclaiming stale group build lock" in r.output

    test "a lock whose owner is alive is waited on":
      let lock = freshLock("alive")
      createDir(lock)
      let p = startProcess("sleep", args = ["30"], options = {poUsePath})
      writeFile(lock / "owner", $p.processID & " " & execCmdEx("hostname").output.strip & "\n")
      let r = sh("acquire_group_lock " & quoteShell(lock) & " 3 && echo got")
      p.terminate(); discard p.waitForExit(); p.close()
      check r.exitCode != 0 and "got" notin r.output
      check "Timed out waiting for group build lock" in r.output

    test "a lock whose PID was reused by another process is taken over":
      let lock = freshLock("reused")
      createDir(lock)
      let p = startProcess("sleep", args = ["30"], options = {poUsePath})
      ## the right PID, alive, but a start time that is not this process's
      writeFile(lock / "owner", $p.processID & " " & execCmdEx("hostname").output.strip & " 1\n")
      let r = sh("acquire_group_lock " & quoteShell(lock) & " 3 && echo got")
      p.terminate(); discard p.waitForExit(); p.close()
      check r.exitCode == 0 and "got" in r.output

    test "a lock without an owner: waited on while young, taken over when old":
      let lock = freshLock("legacy")
      createDir(lock)
      check sh("acquire_group_lock " & quoteShell(lock) & " 3").exitCode != 0
      discard execCmdEx("touch -d '2 minutes ago' " & quoteShell(lock))
      check sh("acquire_group_lock " & quoteShell(lock) & " 3 && echo got").output.contains("got")

    test "release removes the lock":
      let lock = freshLock("release")
      check sh("acquire_group_lock " & quoteShell(lock) & " 3 && release_group_lock " &
               quoteShell(lock)).exitCode == 0
      check not dirExists(lock)

when isMainModule:
  runTests()
