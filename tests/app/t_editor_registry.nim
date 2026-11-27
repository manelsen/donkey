## The daemon's side of pairing editors (E10.2): pending pairings in memory,
## credentials in `state/editors.json` (0600, hashes only).

import std/[os, posix, strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/adapters/filesystem/fs_adapter
import donkey/domain/acp/editor_pairing_pure
import donkey/app/editor_registry

var clock = 1_000_000'i64
var counter = 0'u8

proc fakeRandom(n: int): Result[seq[byte], string] {.gcsafe.} =
  var bytes = newSeq[byte](n)
  inc counter
  for i in 0 ..< n: bytes[i] = byte((int(counter) * 7 + i) mod 256)
  ok(bytes)

proc registry(tag: string): (EditorRegistry, string) =
  let dir = getTempDir() / ("donkey_editor_registry_" & tag)
  removeDir(dir); createDir(dir)
  let path = dir / "state" / "editors.json"
  (newEditorRegistry(newFsAdapter(), path, fakeRandom,
                     proc(): int64 {.gcsafe.} = clock).get, path)

proc runTests*() =
  suite "editor registry":
    test "pair: begin, the person confirms, the editor collects a token for that person":
      let (r, path) = registry("pair")
      let started = r.beginPairing("Zed").get
      check started.code.len == 6 and started.secret.len >= 43
      check r.collectPairing(started.secret).get.state == epsPending
      check r.confirmPairing(started.code, UserId("u-ana")).get == "Zed"
      let done = r.collectPairing(started.secret).get
      check done.state == epsConfirmed and done.token.len >= 43
      check r.personFor(done.token).get == UserId("u-ana")
      ## kept on disk, 0600, hash only
      check fileExists(path)
      var st: Stat
      check stat(path.cstring, st) == 0 and (st.st_mode.int and 0o777) == 0o600
      check done.token notin readFile(path)

    test "the credentials survive a restart and can be revoked":
      let (r, path) = registry("restart")
      let s = r.beginPairing("Zed").get
      discard r.confirmPairing(s.code, UserId("u-ana"))
      let token = r.collectPairing(s.secret).get.token
      let again = newEditorRegistry(newFsAdapter(), path, fakeRandom,
                                    proc(): int64 {.gcsafe.} = clock).get
      check again.personFor(token).get == UserId("u-ana")
      let listed = again.editors()
      check listed.len == 1 and listed[0].name == "Zed"
      check again.revokeEditor(listed[0].id).isOk
      check again.personFor(token).isErr
      let third = newEditorRegistry(newFsAdapter(), path, fakeRandom,
                                    proc(): int64 {.gcsafe.} = clock).get
      check third.personFor(token).isErr

    test "a broken editors file is an error, never an empty registry that overwrites it":
      let dir = getTempDir() / "donkey_editor_registry_broken"
      removeDir(dir); createDir(dir / "state")
      writeFile(dir / "state" / "editors.json", "{broken")
      check newEditorRegistry(newFsAdapter(), dir / "state" / "editors.json", fakeRandom,
                              proc(): int64 {.gcsafe.} = clock).isErr

proc runCommandTests*() =
  suite "editor registry — /editor":
    test "a code confirms; the list shows the person's editors; revoking takes only theirs":
      let (r, _) = registry("command")
      check "Nenhum editor" in r.editorCommand(UserId("u-ana"), "").get
      let s = r.beginPairing("Zed").get
      let confirmed = r.editorCommand(UserId("u-ana"), s.code.toLowerAscii).get
      check "Zed" in confirmed
      discard r.collectPairing(s.secret)
      let s2 = r.beginPairing("Outro").get
      discard r.confirmPairing(s2.code, UserId("u-bob"))
      discard r.collectPairing(s2.secret)
      let listed = r.editorCommand(UserId("u-ana"), "").get
      check "Zed" in listed and "Outro" notin listed
      let anaId = r.editors()[0].id
      let bobId = r.editors()[1].id
      check r.editorCommand(UserId("u-ana"), "revogar " & bobId).isErr   ## not hers
      check r.editors().len == 2
      check r.editorCommand(UserId("u-ana"), "revogar " & anaId).isOk
      check r.editors().len == 1 and r.editors()[0].id == bobId

    test "a revocation written by another process (ctl) takes effect at once":
      let (daemon, path) = registry("ctl")
      let s = daemon.beginPairing("Zed").get
      discard daemon.confirmPairing(s.code, UserId("u-ana"))
      let token = daemon.collectPairing(s.secret).get.token
      let ctl = newEditorRegistry(newFsAdapter(), path, fakeRandom,
                                  proc(): int64 {.gcsafe.} = clock).get
      check ctl.revokeEditor(ctl.editors()[0].id).isOk
      check daemon.personFor(token).isErr

    test "the operator's table: id, person, name; empty says so":
      let (r, _) = registry("table")
      check r.editorTable() == "No paired editors."
      let s = r.beginPairing("Zed").get
      discard r.confirmPairing(s.code, UserId("u-ana"))
      discard r.collectPairing(s.secret)
      let lines = r.editorTable().splitLines
      check lines[0] == "id\tuser\tname"
      check lines[1] == r.editors()[0].id & "\tu-ana\tZed"

    test "an unknown code says so":
      let (r, _) = registry("command-bad")
      check r.editorCommand(UserId("u-ana"), "ZZZZZZ").isErr

when isMainModule:
  runTests()
  runCommandTests()
