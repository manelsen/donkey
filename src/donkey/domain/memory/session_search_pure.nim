## session_search_pure — pure lexical ranking for session/MEMORY search.
##
## No filesystem, ports or async here. The adapter reads and folds records; this
## module owns query normalization, scoring, snippets and deterministic limits.

import std/[algorithm, math, strutils, unicode]

type
  SessionHitKind* = enum
    shkSession = "session"
    shkMemory = "memory"

  SessionSearchRecord* = object
    sessionId*:   string
    kind*:        SessionHitKind
    role*:        string
    text*:        string
    timestampMs*: int64

  SessionHit* = object
    sessionId*:   string
    kind*:        SessionHitKind
    role*:        string
    snippet*:     string
    score*:       float32
    timestampMs*: int64

const
  SessionSearchDefaultLimit* = 10
  SessionSearchMaxLimit*     = 50
  SessionSearchMaxQueryChars* = 500
  SessionSearchSnippetChars* = 240

func foldSearchText*(text: string): string =
  ## Unicode-aware case folding used by both query and records.
  for r in text.runes:
    result.add($toLower(r))

func queryTerms*(query: string): seq[string] =
  ## Splits on non-alphanumeric runes and deduplicates terms.
  var current = ""
  for r in foldSearchText(query).runes:
    if r.isAlpha or (r.int >= 48 and r.int <= 57):
      current.add($r)
    elif current.len > 0:
      if current notin result:
        result.add(current)
      current.setLen(0)
  if current.len > 0 and current notin result:
    result.add(current)

func countOccurrences(haystack, needle: string): int =
  if needle.len == 0:
    return 0
  var pos = 0
  while true:
    let idx = haystack.find(needle, pos)
    if idx < 0:
      break
    inc result
    pos = idx + needle.len

func safeSlice(text: string; start, stop: int): string =
  var first = min(text.len, max(0, start))
  var last = min(text.len, stop)
  if first > last:
    return ""
  while first < last and first < text.len and
        (ord(text[first]) and 0xC0) == 0x80:
    inc first
  while last > first and last < text.len and
        (ord(text[last]) and 0xC0) == 0x80:
    dec last
  text[first ..< last]

func makeSnippet*(text: string; query: string;
                  maxChars = SessionSearchSnippetChars): string =
  ## Returns a bounded UTF-8-safe excerpt around the first query term.
  if text.len == 0:
    return ""
  let folded = foldSearchText(text)
  let terms = queryTerms(query)
  var pos = -1
  for term in terms:
    let found = folded.find(term)
    if found >= 0:
      pos = found
      break
  let start = min(text.len,
    if pos >= 0: max(0, pos - maxChars div 3)
    else: 0)
  let stop = min(text.len, start + maxChars)
  result = safeSlice(text, start, stop)
  if start > 0:
    result = "…" & result
  if stop < text.len:
    result.add("…")

func roleBonus*(role: string): float32 =
  case role
  of "user": 0.6'f32
  of "assistant": 0.3'f32
  of "memory": 0.8'f32
  else: 0.1'f32

func scoreSessionRecord*(record: SessionSearchRecord; query: string;
                         nowMs: int64): float32 =
  let terms = queryTerms(query)
  if terms.len == 0 or record.text.len == 0:
    return 0.0'f32
  let folded = foldSearchText(record.text)
  var matched = 0
  var hits = 0
  for term in terms:
    let count = countOccurrences(folded, term)
    if count > 0:
      inc matched
      hits += count
  if matched == 0:
    return 0.0'f32

  result = float32(matched) + float32(hits) * 0.15'f32
  if matched == terms.len:
    result += 1.0'f32
  let foldedQuery = foldSearchText(query).strip
  if terms.len > 1 and foldedQuery.len > 0 and foldedQuery in folded:
    result += 2.0'f32
  result += roleBonus(record.role)
  if record.timestampMs > 0 and nowMs > record.timestampMs:
    let ageDays = float64(nowMs - record.timestampMs) / 86_400_000.0
    result += float32(0.5 * exp(-ageDays / 30.0))

func clampSessionSearchLimit*(limit: int): int =
  if limit <= 0: SessionSearchDefaultLimit
  elif limit > SessionSearchMaxLimit: SessionSearchMaxLimit
  else: limit

func rankSessionRecords*(records: seq[SessionSearchRecord]; query: string;
                         nowMs: int64;
                         limit = SessionSearchDefaultLimit): seq[SessionHit] =
  let terms = queryTerms(query)
  if terms.len == 0:
    return
  let capped = clampSessionSearchLimit(limit)
  for record in records:
    let score = scoreSessionRecord(record, query, nowMs)
    if score <= 0:
      continue
    result.add(SessionHit(
      sessionId: record.sessionId,
      kind: record.kind,
      role: record.role,
      snippet: makeSnippet(record.text, query),
      score: score,
      timestampMs: record.timestampMs,
    ))
  result.sort(proc(a, b: SessionHit): int =
    if a.score != b.score:
      cmp(b.score, a.score)
    elif a.timestampMs != b.timestampMs:
      cmp(b.timestampMs, a.timestampMs)
    else:
      cmp(a.sessionId, b.sessionId))
  if result.len > capped:
    result.setLen(capped)
