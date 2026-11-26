## Saving an attachment (audit of 26/11, finding 1): the file is created
## exclusively, relative to the attachments directory and without following a
## link, so two saves never take the same name and nothing planted at a name
## is written through.

import std/[os, sequtils, strutils, unittest]
import donkey/core/pipeops
import donkey/ports/attachment_store
import donkey/adapters/filesystem/attachment_store

proc freshPaddock(tag: string): string =
  result = getTempDir() / ("donkey_att_" & tag)
  removeDir(result)
  createDir(result)

proc runTests*() =
  suite "attachment store — exclusive creation":
    test "a taken name gets the next one; nothing is overwritten":
      let dir = freshPaddock("taken") / "attachments"
      createDir(dir)
      writeFile(dir / "foto.png", "old")
      let s = newAttachmentStore().save(dir, "foto.png", @[byte(1), 2, 3])
      check s.isOk and s.get.fileName == "foto_1.png"
      check readFile(dir / "foto.png") == "old"

    test "a link planted at the name is never followed":
      let base = freshPaddock("link")
      let dir = base / "attachments"
      createDir(dir)
      writeFile(base / "alvo.txt", "intacto")
      createSymlink(base / "alvo.txt", dir / "nota.txt")
      let s = newAttachmentStore().save(dir, "nota.txt", @[byte(65)])
      check s.isOk and s.get.fileName != "nota.txt"
      check readFile(base / "alvo.txt") == "intacto"

    test "many saves of the same name at once: all kept, each under its own name":
      let dir = freshPaddock("many") / "attachments"
      createDir(dir)
      var names: seq[string]
      for i in 0 ..< 20:
        let s = newAttachmentStore().save(dir, "doc.pdf", @[byte(i)])
        check s.isOk
        names.add s.get.fileName
      for i in 0 ..< names.len:
        for j in i + 1 ..< names.len: check names[i] != names[j]
      check toSeq(walkFiles(dir / "doc*.pdf")).len == 20

    test "the file is private from its first byte":
      let dir = freshPaddock("perm") / "attachments"
      createDir(dir)
      let s = newAttachmentStore().save(dir, "x.bin", @[byte(0)])
      check s.isOk
      check getFilePermissions(dir / s.get.fileName) == {fpUserRead, fpUserWrite}

when isMainModule:
  runTests()
