## The application layer reaches the file system and processes through ports
## (audit item 8): `ports/fs` for files, so a test can hand it a fake. A call
## straight to `std/os` or `std/osproc` in `src/donkey/app` counts here, and
## `RawIoBudget` only goes down.
##
## Counted, once per occurrence: the file and process calls below, bare
## (`readFile(p)`), qualified by a std module (`os.readFile(p)`), in method
## syntax on anything but a port (`p.readFile()`, `path.fileExists`). A call
## on a port (`fs.readFile(p)`, `ctx.fs.listDir(p)`, `process.run(spec)`)
## does not count: ports are held in values named `fs` or `process`.

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
    "execProcess", "execCmd", "execCmdEx", "execShellCmd", "startProcess",
  ]
  PortReceivers = ["fs", "process"]
  FieldLikeNames = ["lines", "open"]
    ## Also names of fields and other procs (`edit.lines`, a channel's
    ## `open`): after a dot they count only on a std module.
  StdModules = ["os", "osproc", "syncio", "posix", "dirs", "files", "paths"]
  RawIoBudget = 0
    ## 83 when it started (audit item 8, in three parts); none may come back.

func receiverBefore(line: string; dot: int): string =
  ## The identifier just before the dot at `dot`.
  var q = dot
  while q > 0 and isIdentChar(line[q - 1]): dec q
  line[q ..< dot]

func rawIoLines(code: string): seq[int] =
  ## 0-based line of every raw call, once per occurrence.
  let lines = code.splitLines()
  for i, line in lines:
    for name in RawIoCalls:
      var at = line.find(name)
      while at >= 0:
        let before = if at > 0: line[at - 1] else: ' '
        let tail = at + name.len
        let wholeName = not isIdentChar(before) and
                        (tail >= line.len or not isIdentChar(line[tail]))
        if wholeName:
          var after = tail
          while after < line.len and line[after] == ' ': inc after
          let isCall = after < line.len and line[after] == '('
          if before != '.':
            if isCall: result.add i
          else:
            let receiver = receiverBefore(line, at - 1)
            if name in FieldLikeNames:
              if isCall and receiver in StdModules: result.add i
            elif receiver notin PortReceivers:
              result.add i
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
      check rawIoLines(codeOnly("let t = p.readFile()")).len == 1
      check rawIoLines(codeOnly("if shellPath.fileExists: discard")).len == 1
      check rawIoLines(codeOnly("let ok = process.run(spec)")).len == 0
      check rawIoLines(codeOnly("updated.add(edit.lines)")).len == 0
      check rawIoLines(codeOnly("let t = readFile(readFile(p))")).len == 2
      check rawIoLines(codeOnly("q.open(8)")).len == 0
      check rawIoLines(codeOnly("fd = posix.open(p, 0)")).len == 1

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
        checkpoint("go through ports/fs or ports/process instead")
      check sites.len <= RawIoBudget
      if sites.len < RawIoBudget:
        checkpoint("lower RawIoBudget to " & $sites.len)
      check sites.len == RawIoBudget

when isMainModule:
  runTests()
