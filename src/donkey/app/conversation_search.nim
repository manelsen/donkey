## conversation_search.nim — the `session_search` tool over a user's whole
## conversation history.
##
## The transcripts in `{paddock}/sessions/` are read as they are, newest file
## first, through the fs port (see `domain/memory/conversation_search_pure`
## for why there is no index). The scan yields to the event loop after every
## file and stops at a byte and time budget; the answer always says how much
## of the history it covered, so the model knows when to narrow the search
## with a time window instead of trusting a partial "no match".
##
## The current session is searched too: what compaction removed from the
## context is still in its transcript.

import std/[algorithm, sequtils, strutils]
import chronos
import ../core/pipeops
import ../domain/memory/conversation_search_pure
import ../ports/fs

const
  SessionsDirName* = "sessions"
  ScanMaxBytes* = 256 * 1024 * 1024
  ScanMaxFileBytes* = 64 * 1024 * 1024
  ScanDeadlineMs* = 4_000
  PhraseDefaultLimit* = 10
  PhraseMaxLimit* = 30
  RankedDefaultLimit* = 8
  RankedMaxLimit* = 20
  ReadDefaultRadius* = 5
  ReadMaxRadius* = 20

type
  ConversationSearchRequest* = object
    query*:     string   ## ranked terms
    phrase*:    string   ## exact phrase
    sessionId*: string   ## read mode
    around*:    int64    ## read mode: message number; 0 = the last one
    since*:     string
    until*:     string
    limit*:     int
    offset*:    int
    context*:   int = -1 ## phrase: neighbours per side (default 1);
                         ## read: radius (default 5); -1 = the default
    countOnly*: bool
    oldestFirst*: bool
    excludeSessionId*: string  ## a subagent does not search its parent's session

  SessionFile = object
    id:    string
    path:  string
    size:  int64
    mtime: int64   ## ms

func validSessionId*(id: string): bool =
  id.len in 1 .. 128 and id.allCharsInSet({'a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_', '.'}) and
    not id.startsWith(".")

proc sessionFiles(fs: FsRuntimePort; paddockDir, dir: string): Result[seq[SessionFile], string] =
  let entries = fs.listDir(dir)
  if entries.isErr:
    ## A paddock with no sessions directory yet has no history; anything else
    ## (no paddock, no filesystem) is an error, never an empty "no match".
    if fs.entryKind != nil and fs.entryKind(paddockDir) == fekDir and
       fs.entryKind(dir) == fekMissing:
      return ok(newSeq[SessionFile]())
    return err("cannot list past sessions: " & entries.error)
  var files: seq[SessionFile]
  for e in entries.get:
    if e.kind != fekFile or not e.path.endsWith(".jsonl"): continue
    let name = e.path.split('/')[^1]
    files.add(SessionFile(id: name[0 ..< name.len - ".jsonl".len], path: e.path,
                          size: e.size, mtime: e.mtime * 1000))
  files.sort(proc(a, b: SessionFile): int =
    if a.mtime != b.mtime: cmp(b.mtime, a.mtime) else: cmp(a.id, b.id))
  ok(files)

func coverageText(scanned, total: int; stoppedBy: string): string =
  if stoppedBy.len == 0:
    "all " & $total & " sessions"
  else:
    "the newest " & $scanned & " of " & $total & " sessions; stopped by the " &
      stoppedBy & " budget, narrow with since/until"

proc readContent(fs: FsRuntimePort; f: SessionFile): Result[string, string] =
  if f.size > ScanMaxFileBytes: fs.readCapped(f.path, ScanMaxFileBytes)
  else: fs.readFile(f.path)

proc readSession(fs: FsRuntimePort; f: SessionFile): Result[seq[ConvMessage], string] =
  ok(parseTranscriptMessages(f.id, ? readContent(fs, f), f.mtime))

proc searchConversations*(fs: FsRuntimePort; paddockDir: string;
                          req: ConversationSearchRequest;
                          nowMs: int64): Future[Result[string, string]] {.async.} =
  if fs.listDir == nil or fs.readFile == nil:
    return err(Result[string, string], "past sessions are unavailable here")
  let dir = paddockDir & "/" & SessionsDirName
  let sinceMs = parseTimeBound(req.since, nowMs, isUntil = false)
  let untilMs = parseTimeBound(req.until, nowMs, isUntil = true)
  if sinceMs.isErr: return err(Result[string, string], sinceMs.error)
  if untilMs.isErr: return err(Result[string, string], untilMs.error)
  let window = TimeWindow(sinceMs: sinceMs.get, untilMs: untilMs.get)
  let listed = sessionFiles(fs, paddockDir, dir)
  if listed.isErr: return err(Result[string, string], listed.error)
  let files = listed.get

  ## ── read around a message ──
  if req.sessionId.len > 0:
    if not validSessionId(req.sessionId):
      return err(Result[string, string], "not a session id: " & req.sessionId)
    for f in files:
      if f.id == req.sessionId and f.id != req.excludeSessionId:
        let session = readSession(fs, f)
        if session.isErr: return err(Result[string, string], session.error)
        let messages = session.get
        if messages.len == 0:
          return ok(Result[string, string], "Session " & f.id & " is empty.")
        let around = if req.around > 0: req.around else: messages[^1].seq
        let radius = if req.context > 0: min(req.context, ReadMaxRadius) else: ReadDefaultRadius
        return ok(Result[string, string], renderReadWindow(messages, f.id, around, radius))
    return err(Result[string, string], "no session " & req.sessionId)

  let phrase = req.phrase.strip
  let terms = rankTerms(req.query)
  if phrase.len == 0 and terms.len == 0:
    return err(Result[string, string], "'query' is required (or 'phrase', or 'session_id')")

  var ranker = initRanker(terms)
  var matches: seq[PhraseMatch]
  var scanned = 0
  var bytes = 0'i64
  var stoppedBy = ""
  let started = Moment.now()
  for f in files:
    if f.id == req.excludeSessionId:
      continue
    if window.sinceMs > 0 and f.mtime > 0 and f.mtime < window.sinceMs:
      continue   ## last written before the window opened
    if bytes + min(f.size, ScanMaxFileBytes) > ScanMaxBytes and scanned > 0:
      stoppedBy = "size"
      break
    if (Moment.now() - started).milliseconds > ScanDeadlineMs:
      stoppedBy = "time"
      break
    let content = readContent(fs, f)
    inc scanned
    bytes += min(f.size, ScanMaxFileBytes)
    if content.isOk:
      if phrase.len > 0:
        matches.add(phraseMatchesIn(f.id, content.get, f.mtime, phrase,
                                    (if req.context < 0: 1 else: req.context), window))
      else:
        ranker.addTranscript(f.id, content.get, f.mtime, window)
    await sleepAsync(chronos.milliseconds(0))
  let total = files.len - (if req.excludeSessionId.len > 0 and
                              files.anyIt(it.id == req.excludeSessionId): 1 else: 0)
  let coverage = coverageText(
    (if stoppedBy.len > 0: scanned else: total), total, stoppedBy)

  if phrase.len == 0:
    let limit = if req.limit > 0: min(req.limit, RankedMaxLimit) else: RankedDefaultLimit
    return ok(Result[string, string],
              renderRankedHits(ranker.topSessions(limit), req.query, coverage))

  matches.sort(proc(a, b: PhraseMatch): int =
    let order = cmp(a.msg.tsMs, b.msg.tsMs)
    let byTime = if req.oldestFirst: order else: -order
    if byTime != 0: byTime
    elif a.msg.sessionId != b.msg.sessionId: cmp(a.msg.sessionId, b.msg.sessionId)
    else: cmp(a.msg.seq, b.msg.seq))
  if req.countOnly:
    var perSession: seq[(string, int)]
    for m in matches:
      if perSession.len > 0 and perSession[^1][0] == m.msg.sessionId:
        inc perSession[^1][1]
      else:
        var found = false
        for p in perSession.mitems:
          if p[0] == m.msg.sessionId:
            inc p[1]
            found = true
        if not found: perSession.add((m.msg.sessionId, 1))
    var text = $matches.len & " matches for \"" & phrase & "\" (" & coverage & ")"
    if perSession.len > 0:
      text.add(" in " & $perSession.len & " sessions:")
      for (id, n) in perSession[0 ..< min(perSession.len, 30)]:
        text.add("\n- " & id & ": " & $n)
    return ok(Result[string, string], text)
  let limit = if req.limit > 0: min(req.limit, PhraseMaxLimit) else: PhraseDefaultLimit
  let offset = max(0, min(req.offset, matches.len))
  let page = matches[offset ..< min(matches.len, offset + limit)]
  return ok(Result[string, string],
            renderPhraseResults(page, matches.len, offset, phrase, coverage))
