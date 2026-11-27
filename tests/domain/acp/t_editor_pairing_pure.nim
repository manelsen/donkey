## Pairing an editor (E10.2), the device-flow way: the editor asks and shows a
## short code; the person confirms it on a channel where they are known; the
## editor collects its credential with a long secret only it holds. Nothing
## crosses the network that can be guessed.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/acp/editor_pairing_pure

const T0 = 1_000_000'i64

proc runTests*() =
  suite "editor pairing":
    test "begin, confirm by code, collect once by the secret":
      var p = EditorPairings()
      check p.begin("secret-1", "K7QP2M", "Zed", T0).isOk
      check p.collect("secret-1", T0 + 1000).state == epsPending
      check p.confirm("k7qp2m", UserId("u-ana"), T0 + 2000).get == "Zed"   ## case does not matter
      let done = p.collect("secret-1", T0 + 3000)
      check done.state == epsConfirmed and done.userId == UserId("u-ana") and done.name == "Zed"
      check p.collect("secret-1", T0 + 4000).state == epsUnknown           ## once

    test "an unknown or expired code is refused; an expired pairing is gone":
      var p = EditorPairings()
      check p.begin("s", "AAAAAA", "Zed", T0).isOk
      check p.confirm("BBBBBB", UserId("u"), T0).isErr
      check p.confirm("AAAAAA", UserId("u"), T0 + EditorPairingTtlMs + 1).isErr
      check p.collect("s", T0 + EditorPairingTtlMs + 1).state == epsUnknown

    test "a code is confirmed once; a second person cannot take it":
      var p = EditorPairings()
      check p.begin("s", "AAAAAA", "Zed", T0).isOk
      check p.confirm("AAAAAA", UserId("u-ana"), T0).isOk
      check p.confirm("AAAAAA", UserId("u-bob"), T0).isErr
      check p.collect("s", T0).userId == UserId("u-ana")

    test "pending pairings are capped; expired ones make room":
      var p = EditorPairings()
      for i in 0 ..< MaxPendingPairings:
        check p.begin("s" & $i, "C" & $i, "Zed", T0).isOk
      check p.begin("extra", "XX", "Zed", T0).isErr
      check p.begin("extra", "XX", "Zed", T0 + EditorPairingTtlMs + 1).isOk

    test "a code already pending is not reused":
      var p = EditorPairings()
      check p.begin("s1", "AAAAAA", "Zed", T0).isOk
      check p.begin("s2", "AAAAAA", "Zed", T0).isErr

    test "the code the person types: six unambiguous characters":
      let code = pairingCode([0'u8, 1, 2, 3, 200, 255])
      check code.len == 6
      for c in code: check c in PairingAlphabet
      check '0' notin PairingAlphabet and 'O' notin PairingAlphabet and
            '1' notin PairingAlphabet and 'I' notin PairingAlphabet

    test "the editor's name is shown to the person, kept short and printable":
      check editorName("") == "editor"
      check editorName("Zed\n<b>") == "Zed b"
      check editorName("x".repeat(100)).len == 40

when isMainModule:
  runTests()
