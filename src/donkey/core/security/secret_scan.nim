## secret_scan — pure functions for detecting secret-like strings in text.
##
## Used to warn when tool output, HTTP responses, or other external content
## may contain leaked credentials before they enter the conversation history.
##
## Pattern matching uses string prefix masks (KnownPrefixes) and Shannon
## entropy analysis. Conservative by design — false positives are worse than
## false negatives for user experience.
##
## Pipeline topology (pipeops):
##   text |> scanForSecrets              -- unary scan
##   text |>-> entropyAbove(3.5)         -- last-arg threshold test
##   ok(text) >>= checkForSecrets        -- Result chaining (gate in pipeline)

import std/[strutils, math]
import ../pipeops

type
  SecretKind* = enum
    skKnownPrefix    ## matches a known API key prefix (sk-, AKIA, ghp_, …)
    skBearerToken    ## Bearer <long-token>
    skContextualKey  ## key/token/secret/password word followed by long value
    skHighEntropy    ## high Shannon entropy (> EntropyThreshold bits/char)

  SecretFinding* = object
    kind*: SecretKind
    hint*: string   ## first few chars of match + "…" — never exposes the full key

# ── tunables ──────────────────────────────────────────────────────────────────

const
  MinTokenLen      = 20      ## minimum length for a value to look like a secret
  HintPrefixLen    = 6       ## how many chars to keep in the hint
  EntropyThreshold = 3.5'f64 ## bits per char; random API keys typically > 4.0

# ── known provider prefix masks ───────────────────────────────────────────────

const KnownPrefixes = [
  "sk-ant-api03-",   ## Anthropic (new format)
  "sk-ant-",         ## Anthropic (older format)
  "sk-proj-",        ## OpenAI project key
  "sk-",             ## OpenAI / generic
  "AKIA",            ## AWS access key ID
  "ghp_",            ## GitHub personal access token
  "ghs_",            ## GitHub service token
  "gho_",            ## GitHub OAuth token
  "ghr_",            ## GitHub refresh token
  "github_pat_",     ## GitHub fine-grained PAT
  "xoxb-",           ## Slack bot token
  "xoxp-",           ## Slack user token
  "xoxa-",           ## Slack app token
  "xoxs-",           ## Slack session token
  "ya29.",           ## Google OAuth2 access token
  "AIza",            ## Google API key
]

# ── context words that may precede a secret value ─────────────────────────────

const ContextWords = [
  "apikey", "api_key", "api-key",
  "token", "secret", "password", "passwd",
  "credential", "credentials",
]

# ── helpers ───────────────────────────────────────────────────────────────────

func makeHint*(s: string): string =
  let n = min(HintPrefixLen, s.len)
  s[0 ..< n] & "..."

func looksLikeSecretValue(s: string): bool =
  ## Returns true if s is long enough and contains only token-safe characters.
  if s.len < MinTokenLen: return false
  for c in s:
    if c notin {'a'..'z', 'A'..'Z', '0'..'9', '-', '_', '.', '+', '/', '='}:
      return false
  true

func tokenSplit(text: string): seq[string] =
  ## Splits text into tokens on whitespace and common key=value delimiters.
  var current = ""
  for c in text:
    if c in {' ', '\t', '\n', '\r', '"', '\'', ',', ';', '(', ')', '[', ']', '{', '}'}:
      if current.len > 0:
        result.add(current)
        current = ""
    else:
      current.add(c)
  if current.len > 0:
    result.add(current)

# ── entropy ───────────────────────────────────────────────────────────────────

func calculateEntropy*(s: string): float =
  ## Computes Shannon entropy (bits per character) of s.
  ## High values (> 3.5) suggest random/secret content; low-entropy strings
  ## like repeated chars or dictionary words score below 3.0.
  if s.len == 0: return 0.0'f64
  var freq: array[256, int]
  for c in s:
    inc freq[ord(c)]
  let n = s.len.float
  for count in freq:
    if count > 0:
      let p = count.float / n
      result -= p * log2(p)

func entropyAbove*(threshold: float; s: string): bool =
  ## Returns true if s has Shannon entropy > threshold.
  ## Designed for |>-> piping: s |>-> entropyAbove(3.5)
  calculateEntropy(s) > threshold

# ── scanners ──────────────────────────────────────────────────────────────────

func startsWithKnownSecretPrefix*(value: string): bool =
  ## True when value begins with a complete known credential marker.
  ## Used by final-response masking; partial matches are streaming-only.
  for prefix in KnownPrefixes:
    if value.startsWith(prefix):
      return true
  false

func looksLikeSecretPrefix*(token: string): bool =
  ## True when token is, or is a prefix of, a known credential marker.
  ## Used by streaming sanitization to hold back a token split across chunks.
  if token.len == 0:
    return false
  if token.toLowerAscii() == "bearer":
    return true
  for prefix in KnownPrefixes:
    if token.startsWith(prefix):
      return true
    # Partial markers are held back only from 3 chars, so common short words
    # ("AI", "ya", "gh") do not stall the stream.
    if token.len >= 3 and prefix.startsWith(token):
      return true
  false

func assignedValue*(token: string): string =
  ## Value after the first `=` (preferred) or `:`; empty when absent.
  let eq = token.find('=')
  let colon = token.find(':')
  let sep = if eq > 0: eq elif colon > 0: colon else: -1
  if sep > 0: token[sep + 1 .. ^1] else: ""

func scanKnownPrefixes(text: string): seq[SecretFinding] =
  for token in tokenSplit(text):
    ## Strip leading key=value prefix so "api_key=sk-abc…" catches the value.
    let assigned = assignedValue(token)
    let value = if assigned.len > 0: assigned else: token
    if value.len < MinTokenLen: continue
    for prefix in KnownPrefixes:
      if value.startsWith(prefix) and value.len >= prefix.len + 8:
        result.add SecretFinding(kind: skKnownPrefix, hint: makeHint(value))
        break

func scanBearerTokens(text: string): seq[SecretFinding] =
  ## Looks for "Bearer <token>" pattern.
  var lower = text.toLowerAscii()
  var pos = 0
  while pos < lower.len:
    let idx = lower.find("bearer ", pos)
    if idx < 0: break
    let valueStart = idx + "bearer ".len
    ## Collect the token (non-whitespace chars)
    var valueEnd = valueStart
    while valueEnd < lower.len and lower[valueEnd] notin {' ', '\t', '\n', '\r', '"', '\''}:
      inc valueEnd
    let value = text[valueStart ..< valueEnd]
    if looksLikeSecretValue(value):
      result.add SecretFinding(kind: skBearerToken, hint: makeHint(value))
    pos = valueEnd

func looksLikePassword(s: string): bool =
  ## Looser check for contextual keys: any non-whitespace value of length >= MinTokenLen.
  if s.len < MinTokenLen: return false
  for c in s:
    if c in {' ', '\t', '\n', '\r'}: return false
  true

func isContextKeyword*(keyPart: string): bool =
  ## Returns true if keyPart is (or ends with) a known context word.
  for cw in ContextWords:
    if keyPart == cw or
       keyPart.endsWith("_" & cw) or
       keyPart.endsWith("-" & cw):
      return true
  false

func scanContextualKeys(text: string): seq[SecretFinding] =
  ## Looks for contextWord=VALUE or contextWord: VALUE patterns.
  let tokens = tokenSplit(text)
  let lowerTokens = tokenSplit(text.toLowerAscii())
  for i in 0 ..< tokens.len:
    let lw = lowerTokens[i]

    ## Case 1: "keyword=value" or "keyword:value" fused into one token.
    let eq = lw.find('=')
    let sep =
      if eq > 0: eq
      else:
        let col = lw.find(':')
        if col > 0: col else: -1
    if sep > 0:
      let keyPart = lw[0 ..< sep]
      let valPart = tokens[i][sep + 1 .. ^1]
      if isContextKeyword(keyPart) and looksLikePassword(valPart):
        result.add SecretFinding(kind: skContextualKey, hint: makeHint(valPart))
        continue   ## matched in Case 1; skip Case 2 for this token

    ## Case 2: bare context word (or "word:") as standalone token;
    ##         the value is the immediately following token.
    let bareKey = lw.strip(chars = {':', '='})
    if isContextKeyword(bareKey) and i + 1 < tokens.len:
      var val = tokens[i + 1]
      if val.len > 0 and val[0] in {'=', ':'}:
        val = val[1 .. ^1]
      if looksLikePassword(val):
        result.add SecretFinding(kind: skContextualKey, hint: makeHint(val))

func scanHighEntropy(text: string): seq[SecretFinding] =
  ## Flags tokens with Shannon entropy > EntropyThreshold.
  ## Catches random-looking strings that don't match any known prefix mask.
  for token in tokenSplit(text):
    if token.len >= MinTokenLen and (token |>-> entropyAbove(EntropyThreshold)):
      result.add SecretFinding(kind: skHighEntropy, hint: makeHint(token))

# ── public API ────────────────────────────────────────────────────────────────

func scanForSecrets*(text: string): seq[SecretFinding] =
  ## Returns all detected secret-like patterns in `text`.
  ## Conservative: only known prefix masks, contextual heuristics, and high entropy.
  result.add scanKnownPrefixes(text)
  result.add scanBearerTokens(text)
  result.add scanContextualKeys(text)
  result.add scanHighEntropy(text)

func hasSecrets*(text: string): bool =
  ## Convenience predicate; designed for use with |> in boolean pipelines.
  text |> scanForSecrets |> len > 0

func checkForSecrets*(text: string): Result[string, string] =
  ## Returns Ok(text) if clean, Err(hint) if secrets detected.
  ## Designed for >>= chaining: ok(text) >>= checkForSecrets >>= nextStep
  let findings = text |> scanForSecrets
  if findings.len > 0:
    err("secret detected: " & findings[0].hint)
  else:
    ok(text)
