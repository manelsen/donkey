## Confinement of outbound media paths to the paddock.
##
## The lexical policy is pure and lives in domain/tools/path_guard; this test
## covers the filesystem half: canonicalisation of the root and the target,
## the symlink boundary re-check, and fail-closed behaviour. Real files and
## symlinks are created under a temp directory; no network is involved.

import std/[os, strutils, unittest]
import results
import donkey/adapters/filesystem/paths

proc freshDir(tag: string): string =
  result = getTempDir() / ("donkey_media_paths_" & tag & "_" &
                           $getCurrentProcessId())
  removeDir(result)
  createDir(result)

proc canonicalDir(path: string): string =
  canonicalPath(path).get()

suite "resolveConfinedMediaPath — lexical decisions":

  test "a file inside the paddock resolves to its canonical path":
    let root = freshDir("inside")
    defer: removeDir(root)
    createDir(root / "attachments")
    let file = root / "attachments" / "nota.opus"
    writeFile(file, "OPUS")
    let resolved = resolveConfinedMediaPath(root, file)
    check resolved.isOk
    check resolved.get() == canonicalDir(root) / "attachments" / "nota.opus"
    check fileExists(resolved.get())

  test "a relative path is taken from the paddock root":
    let root = freshDir("relative")
    defer: removeDir(root)
    createDir(root / "attachments")
    writeFile(root / "attachments" / "foto.png", "PNG")
    let resolved = resolveConfinedMediaPath(root, "attachments/foto.png")
    check resolved.isOk
    check resolved.get() == canonicalDir(root) / "attachments" / "foto.png"

  test "an absolute path outside is rejected":
    let root = freshDir("outside")
    defer: removeDir(root)
    let resolved = resolveConfinedMediaPath(root, "/etc/passwd")
    check resolved.isErr
    check resolved.error.len > 0
    check "passwd" notin resolved.error

  test "traversal is rejected even when it points at an existing file":
    let root = freshDir("traversal")
    defer: removeDir(root)
    let secret = root & "_secret.txt"
    writeFile(secret, "segredo")
    defer: removeFile(secret)
    check resolveConfinedMediaPath(root, "../" & extractFilename(secret)).isErr
    check fileExists(secret)

  test "a sibling with the same prefix is not inside the paddock":
    let base = freshDir("sibling")
    defer: removeDir(base)
    let root = base / "paddock"
    let sibling = base / "paddock2"
    createDir(root)
    createDir(sibling)
    let file = sibling / "foto.png"
    writeFile(file, "PNG")
    check resolveConfinedMediaPath(root, file).isErr
    check fileExists(file)

  test "empty path, null byte, empty root and root slash are rejected":
    let root = freshDir("degenerate")
    defer: removeDir(root)
    check resolveConfinedMediaPath(root, "").isErr
    check resolveConfinedMediaPath(root, "a" & '\x00' & "b").isErr
    check resolveConfinedMediaPath("", root / "x").isErr
    check resolveConfinedMediaPath("/", "/etc/passwd").isErr

  test "a path that normalises back inside is accepted":
    let root = freshDir("dotdot-inside")
    defer: removeDir(root)
    createDir(root / "sub")
    writeFile(root / "a.txt", "A")
    let resolved = resolveConfinedMediaPath(root, root / "sub" / ".." / "a.txt")
    check resolved.isOk
    check resolved.get() == canonicalDir(root) / "a.txt"

  test "a target that does not exist yet resolves under the root":
    let root = freshDir("missing-target")
    defer: removeDir(root)
    createDir(root / "attachments")
    let resolved = resolveConfinedMediaPath(root, root / "attachments" / "novo.opus")
    check resolved.isOk
    check resolved.get() == canonicalDir(root) / "attachments" / "novo.opus"

  test "a missing root fails closed":
    let root = freshDir("missing-root")
    defer: removeDir(root)
    writeFile(root / "nota.opus", "OPUS")
    check resolveConfinedMediaPath(root / "nao-existe", root / "nota.opus").isErr

suite "resolveConfinedMediaPath — symlinks":

  test "a symlinked file pointing outside is rejected and left untouched":
    let base = freshDir("symlink-out")
    defer: removeDir(base)
    let root = base / "paddock"
    createDir(root)
    let outside = base / "segredo.opus"
    writeFile(outside, "SEGREDO")
    when defined(posix):
      createSymlink(outside, root / "link.opus")
      let resolved = resolveConfinedMediaPath(root, root / "link.opus")
      check resolved.isErr
      check fileExists(outside)
      check readFile(outside) == "SEGREDO"
    else:
      discard

  test "a symlinked attachments directory pointing outside is rejected":
    let base = freshDir("symlink-dir")
    defer: removeDir(base)
    let root = base / "paddock"
    let outsideDir = base / "outside"
    createDir(root)
    createDir(outsideDir)
    writeFile(outsideDir / "foto.png", "PNG")
    when defined(posix):
      createSymlink(outsideDir, root / "attachments")
      let resolved = resolveConfinedMediaPath(root, root / "attachments" / "foto.png")
      check resolved.isErr
      check fileExists(outsideDir / "foto.png")
    else:
      discard

  test "a symlink inside the paddock pointing inside is accepted canonically":
    let root = freshDir("symlink-in")
    defer: removeDir(root)
    writeFile(root / "real.ogg", "OGG")
    when defined(posix):
      createSymlink(root / "real.ogg", root / "link.ogg")
      let resolved = resolveConfinedMediaPath(root, root / "link.ogg")
      check resolved.isOk
      check resolved.get() == canonicalDir(root) / "real.ogg"
      check resolved.get() != canonicalDir(root) / "link.ogg"
      check readFile(resolved.get()) == "OGG"
    else:
      discard

  test "a dangling symlink fails closed":
    let root = freshDir("dangling")
    defer: removeDir(root)
    when defined(posix):
      createSymlink(root / "nao-existe.ogg", root / "dangling.ogg")
      check resolveConfinedMediaPath(root, root / "dangling.ogg").isErr
    else:
      discard

  test "a symlinked root pointing outside is still the root":
    let base = freshDir("symlink-root")
    defer: removeDir(base)
    let realRoot = base / "real-paddock"
    createDir(realRoot)
    writeFile(realRoot / "nota.opus", "OPUS")
    when defined(posix):
      createSymlink(realRoot, base / "paddock")
      let resolved = resolveConfinedMediaPath(base / "paddock",
                                               base / "paddock" / "nota.opus")
      check resolved.isOk
      check resolved.get() == canonicalDir(realRoot) / "nota.opus"
    else:
      discard
