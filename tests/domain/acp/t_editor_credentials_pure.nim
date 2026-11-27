## An editor's credential (E10.2): the editor keeps the token; the daemon keeps
## only its hash, the person it speaks for and a public id to list or revoke.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/acp/editor_credentials_pure

proc runTests*() =
  suite "editor credentials":
    test "the token is stored only as its hash; the token finds its person":
      var creds: seq[EditorCredential]
      creds.add newEditorCredential("tok-secret-1", "ed1", UserId("u-ana"), "Zed", 1000)
      check "tok-secret-1" notin $encodeCredentials(creds)
      check creds.personFor("tok-secret-1").get == UserId("u-ana")
      check creds.personFor("tok-other").isErr
      check creds.personFor("").isErr

    test "round trip through the file, and a broken file is an error":
      let creds = @[newEditorCredential("t1", "ed1", UserId("u-ana"), "Zed", 1000),
                    newEditorCredential("t2", "ed2", UserId("u-bob"), "VS Code", 2000)]
      let back = decodeCredentials($encodeCredentials(creds)).get
      check back.len == 2 and back.personFor("t2").get == UserId("u-bob")
      check back[1].name == "VS Code" and back[1].id == "ed2" and back[1].createdMs == 2000
      check decodeCredentials("not json").isErr
      check decodeCredentials("").get.len == 0   ## no file yet

    test "revoking by id removes only that editor":
      var creds = @[newEditorCredential("t1", "ed1", UserId("u-ana"), "Zed", 1),
                    newEditorCredential("t2", "ed2", UserId("u-ana"), "Zed", 2)]
      check creds.revoke("ed1").isOk
      check creds.personFor("t1").isErr and creds.personFor("t2").isOk
      check creds.revoke("ed9").isErr

    test "the hash is SHA-256 hex":
      check tokenHash("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      check tokenHash("abc").len == 64 and tokenHash("abc") == tokenHash("abc").toLowerAscii

when isMainModule:
  runTests()
