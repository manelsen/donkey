## conversation_search_pure — search over a user's past conversations, the
## pure part.
##
## The transcripts (`sessions/<id>.jsonl`) are the complete, append-only log of
## every conversation. Search reads them as they are: no index to build or keep
## in step, nothing summarised away. That follows "Forget Freely, Grep Later"
## (Yang, Shi and Zhao, arXiv:2611.25123): a lossless raw log searched with
## exact patterns matched or beat structured memory, by far on exact recall
## (values, names, IDs, log lines), where summaries lose the detail.
##
## Three ways in, all over the same messages:
##   - an exact phrase (`phraseMatches`): every message holding it, with its
##     neighbours, under a header naming session, time and message number;
##     output paginated and capped, long lines clipped around the match. This
##     is the paper's tool, for strings the agent has already seen.
##   - ranked terms (`Ranker`): BM25 over messages, best message per session,
##     for when there is no exact string to look for (the paper's stated limit).
##   - reading around a message (`renderReadWindow`), to follow up a hit.
##
## Matching folds case and Latin accents, so "reuniao" finds "Reunião".
## Earlier `session_search` results stored in the transcript are skipped, so a
## search does not find its own past output. No I/O.

import std/[algorithm, json, math, sequtils, strutils, tables, times, unicode]
import ../../core/pipeops

const
  PhraseLineChars* = 300       ## a matched or context line, clipped around the match
  OutputMaxChars* = 6000       ## one response; ends on a whole match
  ReadMessageMaxChars* = 2000  ## one message when reading around a hit
  MaxContext* = 3              ## neighbours on each side of a phrase match
  Bm25K1 = 1.2
  Bm25B = 0.75
  TruncatedMark* = "[…truncated]"
  NotFoundHint* =
    "It may have been said in other words: try a synonym, a shorter word or " &
    "the singular. If it is still not found, say you don't remember it, not " &
    "that it was never said."
    ## Closes an empty result. The tone goes in the result, where the agent
    ## reads it when answering: Supernova's benchmark (BUSCA-bancada, 23/11)
    ## measured fewer confident denials of things said in other words with
    ## it there than with it only in the tool description.
  FoundHint* =
    "If none of the excerpts above answers the question, say you don't " &
    "remember it; don't say it was never said."
    ## Closes a result with excerpts: what matched may be about something
    ## else (the neighbour's dog, when asked about hers).
  SearchToolResultPrefix = "[tool_result name=\"session_search\""

type
  ConvMessage* = object
    sessionId*: string
    seq*:       int64   ## the message's number in its session
    role*:      string
    text*:      string
    tsMs*:      int64

  TimeWindow* = object
    sinceMs*: int64     ## 0 = no lower bound
    untilMs*: int64     ## 0 = no upper bound

  PhraseMatch* = object
    msg*:    ConvMessage
    before*: seq[ConvMessage]
    after*:  seq[ConvMessage]

  RankedHit* = object
    sessionId*:       string
    seq*:             int64
    role*:            string
    tsMs*:            int64
    score*:           float
    snippet*:         string
    matchedMessages*: int

  Candidate = object
    msg:  ConvMessage
    tf:   seq[int]
    len:  int

  Ranker* = object
    ## BM25 over every message added. Only messages holding a term are kept;
    ## the rest count toward N and the average length.
    terms:       seq[string]
    docs:        int
    totalLen:    int
    df:          seq[int]
    candidates:  seq[Candidate]

# ── folding ──────────────────────────────────────────────────────────────────

func foldRuneInto(dst: var string; r: Rune) =
  let lower = toLower(r)
  case lower.int
  of 0xE0 .. 0xE5: dst.add('a')
  of 0xE7: dst.add('c')
  of 0xE8 .. 0xEB: dst.add('e')
  of 0xEC .. 0xEF: dst.add('i')
  of 0xF1: dst.add('n')
  of 0xF2 .. 0xF6, 0xF8: dst.add('o')
  of 0xF9 .. 0xFC: dst.add('u')
  of 0xFD, 0xFF: dst.add('y')
  else: dst.add(lower)

func foldRune(r: Rune): string =
  foldRuneInto(result, r)

func foldInto(dst: var string; text: string; first = 0; last = -1) =
  ## Appends the folded `text[first .. last]`; ASCII is copied without
  ## decoding, which is most of any transcript.
  let stop = if last < 0: text.high else: last
  var i = first
  while i <= stop:
    let c = text[i]
    if ord(c) < 0x80:
      dst.add(if c in {'A' .. 'Z'}: chr(ord(c) + 32) else: c)
      inc i
    else:
      let n = text.runeLenAt(i)
      foldRuneInto(dst, text.runeAt(i))
      i += n

func foldText*(text: string): string =
  ## Lower case without Latin accents: the form both sides are compared in.
  result = newStringOfCap(text.len)
  foldInto(result, text)

func foldWithOffsets(text: string): (string, seq[int]) =
  ## The folded text and, for each of its bytes, where its rune starts in the
  ## original, so a match found in the folded text is shown in the original.
  var folded = ""
  var offsets: seq[int]
  var i = 0
  while i < text.len:
    let r = text.runeAt(i)
    let size = text.runeLenAt(i)
    let f = foldRune(r)
    folded.add(f)
    for _ in 0 ..< f.len:
      offsets.add(i)
    i += size
  offsets.add(text.len)
  (folded, offsets)

func runeStart(text: string; at: int): int =
  result = max(0, min(at, text.len))
  while result > 0 and result < text.len and (ord(text[result]) and 0xC0) == 0x80:
    dec result

func clipAround*(text, phrase: string; width = PhraseLineChars): string =
  ## A one-line excerpt of `text` of about `width` bytes centred on the first
  ## place `phrase` (folded) occurs; the start when it does not.
  let flat = text.replace('\n', ' ').replace('\r', ' ')
  if flat.len <= width:
    return flat
  let (folded, offsets) = foldWithOffsets(flat)
  let at = folded.find(foldText(phrase))
  let centre = if at >= 0: offsets[at] else: 0
  let start = runeStart(flat, max(0, centre - width div 3))
  let stop = runeStart(flat, min(flat.len, start + width))
  result = flat[start ..< stop]
  if start > 0: result = "…" & result
  if stop < flat.len: result.add("…")

# ── transcripts ──────────────────────────────────────────────────────────────

proc parseTranscriptMessages*(sessionId, content: string;
                              fallbackTsMs: int64): seq[ConvMessage] =
  ## The messages of one `sessions/<id>.jsonl`. A line without a number is
  ## numbered by its position; without a time it takes `fallbackTsMs` (the
  ## file's modification time). Empty and malformed lines are skipped.
  var position = 0'i64
  for raw in content.splitLines():
    inc position
    let trimmed = raw.strip()
    if trimmed.len == 0: continue
    var j: JsonNode
    try:
      j = parseJson(trimmed)
    except CatchableError:
      continue
    if j.kind != JObject: continue
    let text = j{"text"}.getStr("")
    if text.len == 0: continue
    let seq = j{"seq"}.getBiggestInt(0).int64
    let ts = j{"ts"}.getBiggestInt(0).int64
    result.add(ConvMessage(sessionId: sessionId,
                           seq: (if seq > 0: seq else: position),
                           role: j{"role"}.getStr(""), text: text,
                           tsMs: (if ts > 0: ts else: fallbackTsMs)))

func inWindow*(m: ConvMessage; w: TimeWindow): bool =
  (w.sinceMs == 0 or m.tsMs >= w.sinceMs) and
    (w.untilMs == 0 or m.tsMs <= w.untilMs)

func searchable(m: ConvMessage): bool =
  not m.text.startsWith(SearchToolResultPrefix)

# ── time bounds ──────────────────────────────────────────────────────────────

func parseTimeBound*(raw: string; nowMs: int64; isUntil: bool): Result[int64, string] =
  ## `7d`, `24h`, `2w` (that long before now) or `YYYY-MM-DD` (UTC; as an
  ## upper bound, the end of that day). Empty = no bound (0).
  let s = raw.strip.toLowerAscii
  if s.len == 0:
    return ok(0'i64)
  if s.len >= 2 and s[^1] in {'h', 'd', 'w'} and s[0 ..< ^1].allCharsInSet(Digits):
    let n = try: parseBiggestInt(s[0 ..< ^1]) except ValueError: -1
    if n < 0 or n > 100_000:
      return err("time bound out of range: " & raw)
    let unit = case s[^1]
      of 'h': 3_600_000'i64
      of 'd': 86_400_000'i64
      else: 604_800_000'i64
    return ok(nowMs - int64(n) * unit)
  if s.len == 10 and s[4] == '-' and s[7] == '-':
    try:
      {.cast(noSideEffect).}:
        let day = parse(s, "yyyy-MM-dd", utc()).toTime.toUnix * 1000
        return ok(if isUntil: day + 86_400_000 - 1 else: day)
    except CatchableError:
      discard
  err("time bound '" & raw & "': use 7d, 24h, 2w or YYYY-MM-DD")

# ── exact phrases ────────────────────────────────────────────────────────────

func phraseMatches*(session: seq[ConvMessage]; phrase: string; context: int;
                    window = TimeWindow()): seq[PhraseMatch] =
  ## The messages of one session (in order) that hold `phrase`, oldest first,
  ## each with up to `context` neighbours on each side.
  let needle = foldText(phrase.strip)
  if needle.len == 0: return
  let radius = max(0, min(context, MaxContext))
  for i, m in session:
    if not m.searchable or not m.inWindow(window): continue
    if needle notin foldText(m.text): continue
    var match = PhraseMatch(msg: m)
    for j in max(0, i - radius) ..< i: match.before.add(session[j])
    for j in i + 1 .. min(session.high, i + radius): match.after.add(session[j])
    result.add(match)

func formatTs(ms: int64): string =
  {.cast(noSideEffect).}:
    fromUnix(ms div 1000).utc.format("yyyy-MM-dd HH:mm") & " UTC"

func header(m: ConvMessage): string =
  "[session " & m.sessionId & " · " & formatTs(m.tsMs) & " · #" & $m.seq & "]"

func renderPhraseResults*(page: seq[PhraseMatch]; total, offset: int;
                          phrase, coverage: string;
                          maxChars = OutputMaxChars): string =
  ## GrepMem's layout: a count line, then each match under its header,
  ## `:` the matching message, `-` a neighbour. Stops on a whole match before
  ## `maxChars` and says the offset to continue from.
  var body = ""
  var shown = 0
  for m in page:
    var entry = header(m.msg) & "\n"
    for c in m.before:
      entry.add("- " & c.role & ": " & clipAround(c.text, phrase) & "\n")
    entry.add(": " & m.msg.role & ": " & clipAround(m.msg.text, phrase) & "\n")
    for c in m.after:
      entry.add("- " & c.role & ": " & clipAround(c.text, phrase) & "\n")
    if shown > 0 and body.len + entry.len > maxChars:
      break
    body.add(entry & "--\n")
    inc shown
  result = $total & " matches for \"" & phrase & "\" (" & coverage & "); "
  if shown == 0:
    result.add("none on this page.\n")
    if total == 0:
      result.add(NotFoundHint & "\n")
    else:
      ## Matches exist; this page is past them (only an offset >= total
      ## gets here, since the first match of a page is always shown).
      result.add("The offset is past the last match: use an offset below " &
                 $total & ".\n")
    return
  result.add("showing " & $(offset + 1) & "-" & $(offset + shown) & "\n\n" & body)
  if offset + shown < total:
    result.add("More: call again with offset=" & $(offset + shown) & ".\n")
  result.add(FoundHint & "\n")

# ── ranked terms (BM25) ──────────────────────────────────────────────────────

func rankTerms*(query: string): seq[string] =
  ## Distinct folded words of the query; words of one or two letters are
  ## dropped when longer ones exist (they occur everywhere).
  var all: seq[string]
  var current = ""
  for c in foldText(query) & " ":
    if c.isAlphaNumeric or ord(c) >= 0x80:
      current.add(c)
    elif current.len > 0:
      if current notin all: all.add(current)
      current = ""
  for t in all:
    if t.runeLen >= 3: result.add(t)
  if result.len == 0: result = all

const StemRunes* = 5
  ## A query word longer than this matches stored words by its first five
  ## letters: "fisioterapia" finds "fisio", "operação" finds "operada".

func stemOf*(term: string): string =
  if term.runeLen > StemRunes: term.runeSubStr(0, StemRunes) else: term

func initRanker*(terms: seq[string]): Ranker =
  ## The ranker keeps the stems (`stemOf`), not the query words: matching,
  ## document frequency and the snippet's anchor all use the stem.
  var stems: seq[string]
  for t in terms:
    stems.add(stemOf(t))
  Ranker(terms: stems, df: newSeq[int](terms.len))

func countPrefixed*(folded, term: string): int =
  ## Words of `folded` that start with `term`.
  var at = folded.find(term)
  while at >= 0:
    if at == 0 or not (folded[at - 1].isAlphaNumeric or ord(folded[at - 1]) >= 0x80):
      inc result
    at = folded.find(term, at + term.len)

func add*(r: var Ranker; session: seq[ConvMessage]; window = TimeWindow()) =
  for m in session:
    if not m.searchable or not m.inWindow(window): continue
    inc r.docs
    r.totalLen += m.text.len
    let folded = foldText(m.text)
    var tf = newSeq[int](r.terms.len)
    var any = false
    for i, t in r.terms:
      tf[i] = countPrefixed(folded, t)
      if tf[i] > 0:
        inc r.df[i]
        any = true
    if any:
      r.candidates.add(Candidate(msg: m, tf: tf, len: m.text.len))

func bm25(r: Ranker; c: Candidate): float =
  let n = float(max(r.docs, 1))
  let avg = max(float(r.totalLen) / n, 1.0)
  for i in 0 ..< r.terms.len:
    if c.tf[i] == 0: continue
    let df = float(r.df[i])
    let idf = ln(1.0 + (n - df + 0.5) / (df + 0.5))
    let tf = float(c.tf[i])
    result += idf * tf * (Bm25K1 + 1) /
              (tf + Bm25K1 * (1 - Bm25B + Bm25B * float(c.len) / avg))

func topSessions*(r: Ranker; limit: int): seq[RankedHit] =
  ## The best message of each session, best sessions first (newer first on a
  ## tie). The count of matching messages in the session is reported, not
  ## scored: a long session should not win by length alone.
  var best = initTable[string, RankedHit]()
  for c in r.candidates:
    let score = r.bm25(c)
    let id = c.msg.sessionId
    if id notin best:
      best[id] = RankedHit(sessionId: id, score: -1)
    var hit = best[id]
    inc hit.matchedMessages
    if score > hit.score:
      var firstTerm = ""
      for i, t in r.terms:
        if c.tf[i] > 0:
          firstTerm = t
          break
      hit.score = score
      hit.seq = c.msg.seq
      hit.role = c.msg.role
      hit.tsMs = c.msg.tsMs
      hit.snippet = clipAround(c.msg.text, firstTerm)
    best[id] = hit
  for hit in best.values:
    result.add(hit)
  result.sort(proc(a, b: RankedHit): int =
    if a.score != b.score: cmp(b.score, a.score)
    elif a.tsMs != b.tsMs: cmp(b.tsMs, a.tsMs)
    else: cmp(a.sessionId, b.sessionId))
  if result.len > limit:
    result.setLen(max(limit, 0))

func renderRankedHits*(hits: seq[RankedHit]; query, coverage: string): string =
  if hits.len == 0:
    return "No past conversation matches \"" & query & "\" (" & coverage & "). " &
      NotFoundHint
  result = $hits.len & " conversations match \"" & query & "\" (" & coverage &
           "), best first. Read around a hit with session_id and around=<#>.\n\n"
  for h in hits:
    result.add("[session " & h.sessionId & " · " & formatTs(h.tsMs) & " · #" &
               $h.seq & " · " & $h.matchedMessages & " matching]\n" &
               h.role & ": " & h.snippet & "\n--\n")
  result.add(FoundHint)

# ── reading around a message ─────────────────────────────────────────────────

func renderReadWindow*(session: seq[ConvMessage]; sessionId: string;
                       around: int64; radius: int): string =
  ## The messages numbered `around - radius .. around + radius`, each clipped
  ## to `ReadMessageMaxChars`.
  var at = -1
  for i, m in session:
    if m.seq == around:
      at = i
      break
  if at < 0:
    return "Session " & sessionId & " has no message #" & $around & "."
  let first = max(0, at - radius)
  let last = min(session.high, at + radius)
  result = "[session " & sessionId & " · messages #" & $session[first].seq &
           "-#" & $session[last].seq & " of " & $session.len & " · " &
           formatTs(session[first].tsMs) & " to " & formatTs(session[last].tsMs) & "]\n"
  for i in first .. last:
    let m = session[i]
    var text = m.text
    if text.len > ReadMessageMaxChars:
      text = text[0 ..< runeStart(text, ReadMessageMaxChars)] & "\n" & TruncatedMark
    result.add((if i == at: "> " else: "  ") & "#" & $m.seq & " " & m.role &
               ": " & text & "\n")

# ── straight from a transcript file ──────────────────────────────────────────
#
# Most lines of most files hold nothing searched for. Each raw line is folded
# and checked first; only a line that may match is parsed. A line with a
# `\u` escape cannot be checked in its raw form and is always parsed.

iterator rawLines(content: string): (int, int, int) =
  ## (position from 1, first byte, last byte) of each line.
  var start = 0
  var position = 0
  while start < content.len:
    var stop = content.find('\n', start)
    if stop < 0: stop = content.len
    inc position
    yield (position, start, stop - 1)
    start = stop + 1

func stringField(line, key: string; value: var string): bool =
  ## The string value of `"key":"…"` in one JSON line, unescaped. Keys are
  ## found by a raw search: an unescaped quote only occurs at string bounds.
  ## False on anything unusual (a `\u` escape), so the caller parses fully.
  let tag = "\"" & key & "\":\""
  let at = line.find(tag)
  if at < 0: return false
  var i = at + tag.len
  value = newStringOfCap(64)
  while i < line.len:
    let c = line[i]
    if c == '"': return true
    if c == '\\':
      if i + 1 >= line.len: return false
      case line[i + 1]
      of 'n': value.add('\n')
      of 't': value.add('\t')
      of 'r': value.add('\r')
      of 'b': value.add('\b')
      of 'f': value.add('\f')
      of '"', '\\', '/': value.add(line[i + 1])
      else: return false
      i += 2
    else:
      value.add(c)
      inc i
  false

func intField(line, key: string): int64 =
  let tag = "\"" & key & "\":"
  let at = line.find(tag)
  if at < 0: return 0
  var i = at + tag.len
  ## A negative or non-numeric value reads as absent (0), as the full parser's
  ## callers treat it: the position or the fallback time is used instead.
  while i < line.len and line[i] in Digits:
    result = result * 10 + int64(ord(line[i]) - ord('0'))
    inc i

proc parseLine(sessionId, content: string; position, first, last: int;
               fallbackTsMs: int64; msg: var ConvMessage): bool =
  if last < first: return false
  let line = content[first .. last]
  var text, role: string
  if stringField(line, "text", text) and stringField(line, "role", role):
    if text.len == 0: return false
    let seq = intField(line, "seq")
    let ts = intField(line, "ts")
    msg = ConvMessage(sessionId: sessionId, seq: (if seq > 0: seq else: position),
                      role: role, text: text,
                      tsMs: (if ts > 0: ts else: fallbackTsMs))
    return true
  let parsed = parseTranscriptMessages(sessionId, line, fallbackTsMs)
  if parsed.len == 0: return false
  msg = parsed[0]
  if "\"seq\"" notin line: msg.seq = position
  true

func mayHold(folded: string; needles: openArray[string]; raw: string;
             first, last: int): bool =
  for n in needles:
    if n in folded: return true
  for i in first ..< last:
    if raw[i] == '\\' and raw[i + 1] == 'u': return true
  false

proc phraseMatchesIn*(sessionId, content: string; fallbackTsMs: int64;
                      phrase: string; context: int;
                      window = TimeWindow()): seq[PhraseMatch] =
  ## `phraseMatches` over a whole transcript file, parsing only what it needs.
  let needle = foldText(phrase.strip)
  if needle.len == 0: return
  let radius = max(0, min(context, MaxContext))
  ## A phrase with characters JSON escapes cannot be found in the raw line.
  let rawCheck = not needle.contains({'"', '\\'}) and
                 not needle.anyIt(ord(it) < 0x20)
  var spans: seq[(int, int, int)]
  var hits: seq[int]
  var folded = ""
  for (position, first, last) in rawLines(content):
    spans.add((position, first, last))
    if not rawCheck:
      hits.add(spans.high)
      continue
    folded.setLen(0)
    foldInto(folded, content, first, last)
    if mayHold(folded, [needle], content, first, last):
      hits.add(spans.high)
  if hits.len == 0: return
  ## Parse the candidate lines and their neighbourhoods once each.
  var parsed = newSeq[(bool, ConvMessage)](spans.len)
  var done = newSeq[bool](spans.len)
  template message(k: int): (bool, ConvMessage) =
    if not done[k]:
      var m: ConvMessage
      let ok = parseLine(sessionId, content, spans[k][0], spans[k][1], spans[k][2],
                         fallbackTsMs, m)
      parsed[k] = (ok, m)
      done[k] = true
    parsed[k]
  for k in hits:
    let (ok, m) = message(k)
    if not ok or not m.searchable or not m.inWindow(window): continue
    if needle notin foldText(m.text): continue
    var match = PhraseMatch(msg: m)
    var j = k - 1
    while j >= 0 and match.before.len < radius:
      let (okB, b) = message(j)
      if okB: match.before.insert(b, 0)
      dec j
    j = k + 1
    while j < spans.len and match.after.len < radius:
      let (okA, a) = message(j)
      if okA: match.after.add(a)
      inc j
    result.add(match)

proc addTranscript*(r: var Ranker; sessionId, content: string;
                    fallbackTsMs: int64; window = TimeWindow()) =
  ## `add` over a whole transcript file. Every line counts toward N and the
  ## average length (by its raw length); only lines that may hold a term are
  ## parsed and scored.
  var folded = ""
  for (position, first, last) in rawLines(content):
    if last < first: continue
    folded.setLen(0)
    foldInto(folded, content, first, last)
    if not mayHold(folded, r.terms, content, first, last):
      inc r.docs
      r.totalLen += last - first + 1
      continue
    var m: ConvMessage
    if not parseLine(sessionId, content, position, first, last, fallbackTsMs, m):
      continue
    if not m.searchable or not m.inWindow(window): continue
    inc r.docs
    let length = last - first + 1
    r.totalLen += length
    let foldedText = foldText(m.text)
    var tf = newSeq[int](r.terms.len)
    var any = false
    for i, t in r.terms:
      tf[i] = countPrefixed(foldedText, t)
      if tf[i] > 0:
        inc r.df[i]
        any = true
    if any:
      ## Keep an excerpt, not the message: a ranked search can hold many
      ## candidates until the corpus statistics are known.
      var excerpt = m
      for i, t in r.terms:
        if tf[i] > 0:
          let p = foldedText.find(t)
          let lo = runeStart(m.text, max(0, p - PhraseLineChars))
          let hi = runeStart(m.text, min(m.text.len, p + 2 * PhraseLineChars))
          excerpt.text = (if lo > 0: "…" else: "") & m.text[lo ..< hi] &
                         (if hi < m.text.len: "…" else: "")
          break
      r.candidates.add(Candidate(msg: excerpt, tf: tf, len: length))
