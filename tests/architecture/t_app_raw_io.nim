## The application layer reaches the file system and processes through ports
## (audit item 8): `ports/fs` for files, so a test can hand it a fake. A call
## straight to `std/os` or `std/osproc` in `src/donkey/app` counts here, and
## `RawIoBudget` only goes down.
##
## Counted: the file and process calls below, bare or qualified by the
## module (`os.readFile`). A call through a value (`fs.readFile`,
## `ctx.fs.listDir`) is a port call and does not count.

import std/[os, strutils, unittest]
import ./t_nim_source

const
  RawIoCalls = [
    "readFile", "writeFile", "lines", "open",
    "fileExists", "dirExists", "symlinkExists",
    "createDir", "existsOrCreateDir", "removeFile", "removeDir",
    "copyFile", "copyDir", "moveFile", "moveDir",
    "walkDir", "walkDirRec", "walkFiles", "walkDirs",
    "getFileSize", "getLastModificationTime", "getFileInfo",
    "setFilePermissions", "getFilePermissions",
    "execProcess", "execCmd", "execCmdEx", "startProcess",
  ]
  StdModules = ["os", "osproc", "syncio", "dirs", "files", "paths"]
  RawIoBudget = 47
    ## 76 when it started; what is left calls processes (sandbox, setup,
    ## service, skills, archives, mermaid, bash) or binds the IPC socket.

func rawIoLines(code: string): seq[int] =
  ## 0-based lines with a raw call: the name followed by `(`, not the tail of
  ## a longer name, and either bare or qualified by a std module.
  let lines = code.splitLines()
  for i, line in lines:
    block scan:
      for name in RawIoCalls:
        var at = line.find(name)
        while at >= 0:
          let before = if at > 0: line[at - 1] else: ' '
          var after = at + name.len
          while after < line.len and line[after] == ' ': inc after
          let isCall = after < line.len and line[after] == '(' and
                       not isIdentChar(before) and
                       (at + name.len >= line.len or not isIdentChar(line[at + name.len]))
          if isCall:
            if before != '.':
              result.add i
              break scan
            var q = at - 1
            while q > 0 and isIdentChar(line[q - 1]): dec q
            if line[q ..< at - 1] in StdModules:
              result.add i
              break scan
          at = line.find(name, at + 1)

proc runTests*() =
  suite "raw I/O in the application layer":
    test "bare and std-qualified calls count; port calls do not":
      check rawIoLines(codeOnly("let t = readFile(p)")).len == 1
      check rawIoLines(codeOnly("let t = os.readFile(p)")).len == 1
      check rawIoLines(codeOnly("for k, e in walkDir(p): discard")).len == 1
      check rawIoLines(codeOnly("let r = execCmdEx(cmd)")).len == 1
      check rawIoLines(codeOnly("let t = fs.readFile(p)")).len == 0
      check rawIoLines(codeOnly("let t = ctx.fs.listDir(p)")).len == 0
      check rawIoLines(codeOnly("## readFile(p) in a comment")).len == 0
      check rawIoLines(codeOnly("let s = \"readFile(p)\"")).len == 0
      check rawIoLines(codeOnly("let t = myReadFile(p)")).len == 0
      check rawIoLines(codeOnly("let t = readFileResult(p)")).len == 0
      check rawIoLines(codeOnly("let n = text.splitLines()")).len == 0

    test "raw calls in src/donkey/app stay within a budget that only goes down":
      var sites: seq[string]
      for path in walkDirRec("src/donkey/app"):
        if not path.endsWith(".nim"): continue
        let src = readFile(path)
        let lines = src.splitLines()
        for i in rawIoLines(codeOnly(src)):
          sites.add path & ":" & $(i + 1) & "  " & lines[i].strip
      checkpoint($sites.len & " raw I/O calls in src/donkey/app")
      if sites.len > RawIoBudget:
        for site in sites: checkpoint(site)
        checkpoint("go through ports/fs (or another port) instead")
      check sites.len <= RawIoBudget
      if sites.len < RawIoBudget:
        checkpoint("lower RawIoBudget to " & $sites.len)
      check sites.len == RawIoBudget

when isMainModule:
  runTests()
