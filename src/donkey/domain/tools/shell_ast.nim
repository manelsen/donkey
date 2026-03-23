## Safe Shell AST — pure functions to detect and block shell operators.
##
## All functions are `func` (no side effects, no exceptions, no I/O).
## Use `|>` chaining for composing validations.
##
## Shell operators blocked: ; | & < > ; && || >> 2> 2>&1

import std/[strutils, unicode]

# ── Operator Detection ─────────────────────────────────────────────────────────

func isShellOperatorChar*(c: char): bool =
  ## Returns true if character is a shell operator character.
  c == ';' or c == '|' or c == '&' or c == '<' or c == '>'

func containsShellOperators*(input: string): bool =
  ## Fast pre-check: returns true if input contains any shell operator characters.
  for c in input:
    if isShellOperatorChar(c):
      return true
  false

# ── Specific Operator Detection ───────────────────────────────────────────────

func hasPipe*(input: string): bool =
  ## Returns true if input contains pipe operator `|`.
  '|' in input

func hasSemicolon*(input: string): bool =
  ## Returns true if input contains command separator `;`.
  ';' in input

func hasAmpersand*(input: string): bool =
  ## Returns true if input contains background/AND operator `&`.
  ## Note: also catches `&&`.
  '&' in input

func hasInputRedirect*(input: string): bool =
  ## Returns true if input contains input redirect operator `<`.
  '<' in input

func hasOutputRedirect*(input: string): bool =
  ## Returns true if input contains output redirect operator `>`.
  ## Note: also catches `>>` (append) and `2>` (stderr).
  '>' in input

func hasCommandSeparator*(input: string): bool =
  ## Returns true if input contains sequential command separator `;`.
  ';' in input

func hasLogicalAnd*(input: string): bool =
  ## Returns true if input contains logical AND operator `&&`.
  input.contains("&&")

func hasLogicalOr*(input: string): bool =
  ## Returns true if input contains logical OR operator `||`.
  input.contains("||")

func hasOutputAppend*(input: string): bool =
  ## Returns true if input contains output append operator `>>`.
  input.contains(">>")

func hasStderrRedirect*(input: string): bool =
  ## Returns true if input contains stderr redirect `2>` or `2>&1`.
  input.contains("2>")

# ── Compound Operator Detection ───────────────────────────────────────────────

func hasBackgroundOperator*(input: string): bool =
  ## Returns true if input contains background operator `&`.
  ## This is dangerous as it allows running commands in background.
  '&' in input

func hasRedirect*(input: string): bool =
  ## Returns true if input contains any redirect operator (<, >, >>, 2>).
  '<' in input or '>' in input

func hasCompoundOperator*(input: string): bool =
  ## Returns true if input contains compound operators (&&, ||, >>, 2>, 2>&1).
  input.contains("&&") or input.contains("||") or
  input.contains(">>") or input.contains("2>")

# ── Validation Types ───────────────────────────────────────────────────────────

type
  ShellOperatorKind* = enum
    sokNone           = "no shell operators"
    sokPipe           = "pipe (|)"
    sokSemicolon      = "command separator (;)"
    sokAmpersand      = "background/AND operator (&)"
    sokInputRedirect  = "input redirect (<)"
    sokOutputRedirect = "output redirect (>)"
    sokLogicalAnd     = "logical AND (&&)"
    sokLogicalOr      = "logical OR (||)"
    sokOutputAppend   = "output append (>>)"
    sokStderrRedirect = "stderr redirect (2>)"
    sokCompound       = "compound operator"

  ShellValidation* = object
    case isClean*: bool
    of false:
      operators*: seq[ShellOperatorKind]
    of true:
      normalized*: string

# ── Main Validation ────────────────────────────────────────────────────────────

func detectShellOperators*(input: string): seq[ShellOperatorKind] =
  ## Detect all shell operators present in the input.
  ## Returns a sequence of all operator kinds found.
  if hasLogicalAnd(input):
    result.add(sokLogicalAnd)
  if hasLogicalOr(input):
    result.add(sokLogicalOr)
  if hasOutputAppend(input):
    result.add(sokOutputAppend)
  if hasStderrRedirect(input):
    result.add(sokStderrRedirect)
  elif hasOutputRedirect(input):
    result.add(sokOutputRedirect)
  # Use loop-based detection to avoid double-counting || as pipe
  var i = 0
  while i < input.len:
    if input[i] == '|':
      # Skip if this | is part of || (check next char)
      if i + 1 < input.len and input[i + 1] == '|':
        # This is ||, already detected by hasLogicalOr, skip both chars
        i += 2
        continue
      result.add(sokPipe)
    i += 1
  if hasSemicolon(input):
    result.add(sokSemicolon)
  # Use loop-based detection to avoid double-counting && as ampersand
  i = 0
  while i < input.len:
    if input[i] == '&':
      # Skip if this & is part of && (check next char)
      if i + 1 < input.len and input[i + 1] == '&':
        # This is &&, already detected by hasLogicalAnd, skip both chars
        i += 2
        continue
      result.add(sokAmpersand)
    i += 1
  if hasInputRedirect(input):
    result.add(sokInputRedirect)

func validateShellSafe*(input: string): ShellValidation =
  ## Validate that input contains no shell operators.
  ## Returns ShellValidation with normalized input on success,
  ## or sequence of detected operators on failure.
  let detected = detectShellOperators(input)
  if detected.len == 0:
    ShellValidation(isClean: true, normalized: input.strip())
  else:
    ShellValidation(isClean: false, operators: detected)

func isShellSafe*(input: string): bool =
  ## Returns true when input contains no shell operators.
  not containsShellOperators(input)

# ── Error Messages ─────────────────────────────────────────────────────────────

func shellValidationErrorMsg*(input: string): string =
  let v = validateShellSafe(input)
  if v.isClean:
    return "Error: invalid input"
  let ops = v.operators
  if ops.len == 1:
    return "Error: shell operator blocked: " & $ops[0]
  var names: seq[string] = @[]
  for op in ops:
    names.add($op)
  return "Error: shell operators blocked (multiple): " & names.join(", ")

func shellBlockReason*(input: string): string =
  ## Returns human-readable reason for why input was blocked.
  let v = validateShellSafe(input)
  if v.isClean:
    return "input is clean"
  let ops = v.operators
  if ops.len == 1:
    return "contains " & $ops[0]
  var names: seq[string] = @[]
  for op in ops:
    names.add($op)
  return "contains multiple operators: " & names.join(", ")
