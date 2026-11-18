## Path Security Sandbox — pure functions to block traversal and restrict to workspace.
##
## All functions are `func` (no side effects, no exceptions, no I/O).
## Use `|>` chaining for composing validations.

import std/[strutils]

# ── Normalization ─────────────────────────────────────────────────────────────

func normalizePath*(raw: string): string =
  ## Normalize a path: collapse multiple slashes, resolve . and ..
  ## Returns empty string for empty input.
  if raw.len == 0:
    return ""
  var parts: seq[string] = @[]
  var abs = false
  let toProcess = if raw[0] == '/': abs = true; raw[1 .. ^1] else: raw
  for tok in toProcess.split('/'):
    if tok.len == 0 or tok == ".":
      discard
    elif tok == "..":
      if parts.len > 0 and parts[^1] != "..":
        discard parts.pop()
      elif not abs:
        parts.add(tok)
    else:
      parts.add(tok)
  if abs: "/" & parts.join("/")
  elif parts.len == 0: "."
  else: parts.join("/")

func splitPath*(path: string): (string, string) =
  ## Split path into (directory, filename). "." / "/" if no directory.
  let norm = normalizePath(path)
  let lastSlash = norm.rfind('/')
  if lastSlash < 0:
    # No slash at all
    if norm.len == 0: (".", ".")
    else: (".", norm)
  elif lastSlash == 0:
    # Root-level: "/foo.txt" -> ("/", "foo.txt")
    ("/", if norm.len > 1: norm[1 .. ^1] else: "")
  else:
    (norm[0 ..< lastSlash], norm[lastSlash + 1 .. ^1])

# ── Traversal Detection ────────────────────────────────────────────────────────

func containsPathTraversal*(path: string): bool =
  ## Fast pre-check: returns true if path contains `..` or normalizes to a traversal.
  ## This is a quick heuristic — use isPathTraversalAttempt for precision.
  if path == "..": return true
  if path.contains("../"): return true
  let norm = normalizePath(path)
  if norm.contains(".."): return true
  if norm == "..": return true
  if norm.startsWith("../"): return true
  false

func isPathTraversalAttempt*(path: string): bool =
  ## Returns true when path attempts directory traversal.
  ## Detects: paths where original or normalized form contains .. or escapes root.
  if path.len == 0:
    return false
  if path == "..": return true
  if path.contains("../"): return true
  let norm = normalizePath(path)
  # If normalized path still has .., it would escape after normalization
  if norm.contains(".."): return true
  # If path tries to escape above root after normalization
  if norm == "..": return true
  if norm.startsWith("../"): return true
  false

# ── Workspace Containment ─────────────────────────────────────────────────────

func isPathInDirectory*(path, workspace: string): bool =
  ## Returns true when `path`, after normalization, is contained within `workspace`.
  ## Both paths are normalized before comparison.
  ## Empty workspace means no restriction (returns true).
  if workspace.len == 0:
    return true
  let normPath = normalizePath(path)
  let normWorkspace = normalizePath(workspace)
  # Absolute path check
  if normPath[0] == '/':
    if normWorkspace[0] == '/':
      return normPath.startsWith(normWorkspace) and
             (normPath.len == normWorkspace.len or normPath[normWorkspace.len] == '/')
    return false
  # Relative path vs absolute workspace: prepend workspace
  if normWorkspace[0] == '/':
    let absPath = normWorkspace & "/" & normPath
    return absPath == normalizePath(absPath)
  # Both relative
  return normPath.startsWith(normWorkspace) and
         (normPath.len == normWorkspace.len or normPath[normWorkspace.len] == '/')

func isPathSafe*(path: string; workspace = ""): bool =
  ## Returns true when the path is safe: no traversal, no null bytes, and within workspace if set.
  if path.len == 0:
    return false
  if '\x00' in path:
    return false
  if isPathTraversalAttempt(path):
    return false
  if workspace.len > 0 and not isPathInDirectory(path, workspace):
    return false
  true

# ── Validation Result ───────────────────────────────────────────────────────────

type
  PathValidationError* = enum
    pveEmptyPath         = "path is empty"
    pveTraversalAttempt  = "path traversal detected"
    pveOutsideWorkspace  = "path is outside the allowed workspace"
    pveNullByte          = "null byte in path"

  PathValidation* = object
    case ok*: bool
    of false:
      error*: PathValidationError
    of true:
      normalized*: string

func validatePathAccess*(path: string; workspace = ""): PathValidation =
  ## Validate a path for safe access. Returns PathValidation with normalized
  ## path on success, or error kind on failure.
  if path.len == 0:
    return PathValidation(ok: false, error: pveEmptyPath)
  if '\x00' in path:
    return PathValidation(ok: false, error: pveNullByte)
  if isPathTraversalAttempt(path):
    return PathValidation(ok: false, error: pveTraversalAttempt)
  if workspace.len > 0 and not isPathInDirectory(path, workspace):
    return PathValidation(ok: false, error: pveOutsideWorkspace)
  PathValidation(ok: true, normalized: normalizePath(path))

# ── Outbound media confinement ────────────────────────────────────────────────

type
  OutboundMediaKind* = enum
    mpkRemote    ## explicit http(s) URL; the channel sends the URL
    mpkLocal     ## local path contained in the paddock
    mpkRejected  ## empty, malformed, root-less or outside the paddock

  OutboundMediaPath* = object
    kind*: OutboundMediaKind
    lexicalPath*: string  ## normalized candidate; set only for mpkLocal
    reason*: string       ## path-free explanation; empty on success

func isRemoteMediaPath(raw: string): bool =
  ## Only an explicit http(s) URL travels as a remote reference. The check is
  ## case-insensitive and tolerant of surrounding whitespace, like the adapter.
  let lower = raw.strip.toLowerAscii()
  lower.startsWith("http://") or lower.startsWith("https://")

func classifyOutboundMediaPath*(paddockRoot, raw: string): OutboundMediaPath =
  ## Classifies outbound media as remote, local-inside or rejected. Pure: the
  ## decision normalizes `.`, `..` and repeated separators first, compares on
  ## segment boundaries (so `/paddock2` is not inside `/paddock`), and never
  ## puts the path or the root into `reason`.
  if raw.len == 0:
    return OutboundMediaPath(kind: mpkRejected, reason: "media path is empty")
  if '\x00' in raw:
    return OutboundMediaPath(kind: mpkRejected,
                             reason: "media path contains a null byte")
  if isRemoteMediaPath(raw):
    return OutboundMediaPath(kind: mpkRemote, reason: "remote media URL")
  if paddockRoot.len == 0:
    return OutboundMediaPath(kind: mpkRejected,
                             reason: "no paddock root configured")
  let normRoot = normalizePath(paddockRoot)
  if normRoot.len == 0 or normRoot == "/":
    return OutboundMediaPath(kind: mpkRejected,
                             reason: "invalid paddock root")
  let normRaw = normalizePath(raw)
  if normRaw.len == 0:
    return OutboundMediaPath(kind: mpkRejected, reason: "media path is empty")
  let candidate =
    if normRaw[0] == '/' or normRoot == ".":
      normRaw
    else:
      normalizePath(normRoot & "/" & normRaw)
  let inside =
    if normRoot == ".":
      candidate != ".." and not candidate.startsWith("../") and
        candidate[0] != '/'
    else:
      candidate == normRoot or candidate.startsWith(normRoot & "/")
  if not inside:
    return OutboundMediaPath(kind: mpkRejected,
                             reason: "media path is outside the paddock")
  OutboundMediaPath(kind: mpkLocal, lexicalPath: candidate, reason: "")

# ── Error Messages ─────────────────────────────────────────────────────────────

func pathAccessErrorMsg*(path: string; workspace = ""): string =
  let v = validatePathAccess(path, workspace)
  if v.ok:
    return "Error: invalid path"
  case v.error
  of pveEmptyPath:      "Error: path is empty"
  of pveTraversalAttempt: "Error: path traversal attempt blocked ('" & path & "')"
  of pveOutsideWorkspace:  "Error: path '" & path & "' is outside the allowed workspace"
  of pveNullByte:         "Error: null byte in path"
