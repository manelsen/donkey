## Compaction (E8.5), the pure half: when to compact, where to cut, what the
## summary request and the compacted history look like.
##
## Decided on 26/11: compact past 40% of a 1M-token context, 60% of a smaller
## one; the summary is written by the session's own model. Compaction is a
## step, never a sliding window: the prompt cache keeps working between
## steps. Right after a turn the cache is warm, so a history just past the
## threshold waits for an idle pause (the 5-minute cache has expired anyway);
## one well past it is compacted at once.

import std/strutils
import ./message

const
  LargeContext* = 1_000_000
  UnknownContext* = 128_000       ## assumed when the model's window is unknown
  CacheTtlMs* = 300_000'i64       ## the prompt cache's 5 minutes
  SummaryHeading* = "## Resumo da conversa anterior"
  SummarySystem* =
    "You are compacting a long conversation so it can go on. Write a summary " &
    "for yourself, in the language of the conversation: what the person asked " &
    "for and decided, facts they gave, names, numbers, file paths and links, " &
    "what was done and what is still open, commitments made. Keep what a " &
    "later turn may need; drop chatter. No preamble, no closing remarks."

func compactionThreshold*(contextWindow: int): int =
  let window = if contextWindow > 0: contextWindow else: UnknownContext
  if window >= LargeContext: window * 40 div 100 else: window * 60 div 100

func messageTokens(m: ChatMessage): int =
  var chars = m.text.len + m.reasoning.len + m.turnContext.len
  for tc in m.toolCalls: chars += tc.name.len + tc.inputJson.len
  chars div 4 + 4

func estimateTokens*(history: ConversationHistory): int =
  ## About four characters a token, plus a little per message.
  for m in history: result += messageTokens(m)

func shouldCompact*(tokens, window: int; idleMs: int64): bool =
  let threshold = compactionThreshold(window)
  if tokens < threshold: return false
  idleMs >= CacheTtlMs or tokens >= threshold + threshold div 4

func isPersonTurn(m: ChatMessage): bool =
  m.role == "user" and m.toolCallId.len == 0

func splitForCompaction*(history: ConversationHistory;
                         keepTokens: int): (ConversationHistory, ConversationHistory) =
  ## The old part and the tail to keep. The tail holds about `keepTokens` and
  ## starts at a person's message, so a tool call is never apart from its
  ## result; when even the last exchange is larger, the tail is that exchange.
  if history.len == 0: return (history, history)
  var start = history.len
  var used = 0
  while start > 0 and used + messageTokens(history[start - 1]) <= keepTokens:
    dec start
    used += messageTokens(history[start])
  var cut = -1
  for i in start ..< history.len:
    if isPersonTurn(history[i]):
      cut = i
      break
  if cut < 0:
    for i in countdown(history.high, 0):
      if isPersonTurn(history[i]):
        cut = i
        break
  if cut <= 0: return (newHistory(), history)
  (history[0 ..< cut], history[cut .. ^1])

func transcriptOf(old: ConversationHistory): string =
  var lines: seq[string]
  for m in old:
    if m.toolCallId.len > 0:
      lines.add "tool result: " & m.text
    else:
      var line = m.role & ": " & m.text
      for tc in m.toolCalls: line.add "\n  [called " & tc.name & " " & tc.inputJson & "]"
      lines.add line
  lines.join("\n\n")

func summaryRequest*(old: ConversationHistory): CompletionRequest =
  var h = newHistory()
  h.addUser("The conversation to summarize:\n\n" & transcriptOf(old))
  CompletionRequest(system: SummarySystem, messages: h)

func compactedHistory*(summary: string; tail: ConversationHistory): ConversationHistory =
  ## The summary first, as a message nobody said (never in the transcript),
  ## then the tail as it was.
  result = @[ChatMessage(role: "user", text: SummaryHeading & "\n" & summary.strip,
                         seq: SyntheticMessageSeq)]
  result.add tail
