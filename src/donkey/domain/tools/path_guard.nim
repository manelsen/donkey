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
