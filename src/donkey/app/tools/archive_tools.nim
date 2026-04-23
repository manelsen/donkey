## archive_tools.nim — structured archive create/extract helpers.
##
## Uses system archive utilities behind a structured contract and performs
## preflight path checks to block traversal before extraction.

import std/[json, os, osproc, strutils]
import results
import ../../core/tooling/structured_tool_result
import ../../domain/tools/path_guard
import ./fs_tools

type
  ArchiveFormat = enum
    afZip
    afTar
    afTarGz

proc detectArchiveFormat(path: string): Result[ArchiveFormat, string] {.gcsafe, raises: [].} =
  let lower = path.toLowerAscii()
  if lower.endsWith(".zip"):
    ok(afZip)
  elif lower.endsWith(".tar.gz") or lower.endsWith(".tgz"):
    ok(afTarGz)
  elif lower.endsWith(".tar"):
    ok(afTar)
  else:
    err("unsupported archive format: " & path)

proc runCommand(argv: seq[string]; workingDir = ""): tuple[output: string, code: int] {.gcsafe, raises: [].} =
  try:
    let cmd = quoteShellCommand(argv)
    let (output, exitCode) = execCmdEx(cmd,
                                       options = {poUsePath, poStdErrToStdOut},
                                       workingDir = workingDir)
    (output: output, code: exitCode)
  except CatchableError as e:
    (output: e.msg, code: 127)

proc resolveArchivePath(path, paddockDir: string): Result[string, string] {.gcsafe, raises: [].} =
  if path.strip().len == 0:
    return err("archive path is required")
  let resolved = resolveInPaddock(path, paddockDir)
  if not inPaddock(resolved, paddockDir):
    return err("archive path outside paddock: " & path)
  ok(resolved)

proc resolveWorkspacePath(path, paddockDir, field: string): Result[string, string] {.gcsafe, raises: [].} =
  if path.strip().len == 0:
    return err(field & " is required")
  let resolved = resolveInPaddock(path, paddockDir)
  if not inPaddock(resolved, paddockDir):
    return err(field & " outside paddock: " & path)
  ok(resolved)

proc hasTool(name: string): bool {.gcsafe, raises: [].} =
  try:
    findExe(name).len > 0
  except CatchableError:
    false

proc ensureArchiveTool(format: ArchiveFormat; action: string): Result[seq[string], string] {.gcsafe, raises: [].} =
  case format
  of afZip:
    case action
    of "list":
      if not hasTool("unzip"): return err("unzip not found")
      ok(@["unzip", "-Z1"])
    of "extract":
      if not hasTool("unzip"): return err("unzip not found")
      ok(@["unzip", "-oq"])
    of "create":
      if not hasTool("zip"): return err("zip not found")
      ok(@["zip", "-rq"])
    else:
      err("unsupported archive operation")
  of afTar:
    case action
    of "list":
      if not hasTool("tar"): return err("tar not found")
      ok(@["tar", "-tf"])
    of "extract":
      if not hasTool("tar"): return err("tar not found")
      ok(@["tar", "-xf"])
    of "create":
      if not hasTool("tar"): return err("tar not found")
      ok(@["tar", "-cf"])
    else:
      err("unsupported archive operation")
  of afTarGz:
    case action
    of "list":
      if not hasTool("tar"): return err("tar not found")
      ok(@["tar", "-tf"])
    of "extract":
      if not hasTool("tar"): return err("tar not found")
      ok(@["tar", "-xf"])
    of "create":
      if not hasTool("tar"): return err("tar not found")
      ok(@["tar", "-czf"])
    else:
      err("unsupported archive operation")

proc listArchiveEntries(resolvedArchive: string; format: ArchiveFormat): Result[seq[string], string] {.gcsafe, raises: [].} =
  let baseCmd = ensureArchiveTool(format, "list").valueOr:
    return err(error)
  let (outp, code) = runCommand(baseCmd & @[resolvedArchive])
  if code != 0:
    return err(outp.strip())
  var entries: seq[string] = @[]
  for rawLine in outp.splitLines():
    let entry = rawLine.strip()
    if entry.len > 0:
      entries.add(entry)
  ok(entries)

proc validateArchiveEntries(entries: seq[string]): Result[void, string] {.gcsafe, raises: [].} =
  if entries.len == 0:
    return err("archive contains no entries")
  for entry in entries:
    if entry.startsWith("/"):
      return err("archive entry is absolute: " & entry)
    let validation = validatePathAccess(entry)
    if not validation.ok:
      return err("unsafe archive entry: " & entry)
  ok()

proc performArchiveExtract*(archivePath, destinationDir, paddockDir: string): StructuredToolResult {.gcsafe, raises: [].} =
  if paddockDir.len == 0:
    return usageErrorToolResult("paddock is required")

  let resolvedArchive = resolveArchivePath(archivePath, paddockDir).valueOr:
    return usageErrorToolResult(error)
  let resolvedDestination = resolveWorkspacePath(destinationDir, paddockDir, "destination").valueOr:
    return usageErrorToolResult(error)
  if not fileExists(resolvedArchive):
    return operationalErrorToolResult("archive not found: " & archivePath)

  let format = detectArchiveFormat(resolvedArchive).valueOr:
    return usageErrorToolResult(error)

  let entries = listArchiveEntries(resolvedArchive, format).valueOr:
    return operationalErrorToolResult(error)
  let validation = validateArchiveEntries(entries)
  if validation.isErr:
    return operationalErrorToolResult(validation.error)

  try:
    createDir(resolvedDestination)
  except CatchableError as e:
    return operationalErrorToolResult(e.msg)

  let baseCmd = ensureArchiveTool(format, "extract").valueOr:
    return operationalErrorToolResult(error)
  let argv = case format
    of afZip: baseCmd & @[resolvedArchive, "-d", resolvedDestination]
    of afTar, afTarGz: baseCmd & @[resolvedArchive, "-C", resolvedDestination]
  let (outp, code) = runCommand(argv)
  if code != 0:
    return operationalErrorToolResult(outp.strip())

  successToolResult(%*{
    "archive_path": relativeToPaddock(resolvedArchive, paddockDir),
    "destination": relativeToPaddock(resolvedDestination, paddockDir),
    "format": $format,
    "entry_count": entries.len,
    "entries": entries,
  })

proc performArchiveCreate*(archivePath: string; inputs: seq[string]; paddockDir: string): StructuredToolResult {.gcsafe, raises: [].} =
  if paddockDir.len == 0:
    return usageErrorToolResult("paddock is required")
  if inputs.len == 0:
    return usageErrorToolResult("at least one input path is required")

  let resolvedArchive = resolveArchivePath(archivePath, paddockDir).valueOr:
    return usageErrorToolResult(error)
  let format = detectArchiveFormat(resolvedArchive).valueOr:
    return usageErrorToolResult(error)

  var relativeInputs: seq[string] = @[]
  for inputPath in inputs:
    let resolvedInput = resolveWorkspacePath(inputPath, paddockDir, "input").valueOr:
      return usageErrorToolResult(error)
    if not dirExists(resolvedInput) and not fileExists(resolvedInput):
      return operationalErrorToolResult("path not found: " & inputPath)
    relativeInputs.add(relativeToPaddock(resolvedInput, paddockDir))

  try:
    createDir(parentDir(resolvedArchive))
  except CatchableError as e:
    return operationalErrorToolResult(e.msg)

  let baseCmd = ensureArchiveTool(format, "create").valueOr:
    return operationalErrorToolResult(error)
  let argv = baseCmd & @[resolvedArchive] & relativeInputs
  let (outp, code) = runCommand(argv, paddockDir)
  if code != 0:
    return operationalErrorToolResult(outp.strip())

  successToolResult(%*{
    "archive_path": relativeToPaddock(resolvedArchive, paddockDir),
    "format": $format,
    "entry_count": relativeInputs.len,
    "entries": relativeInputs,
  })
