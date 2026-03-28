## compaction_pure — Pure session context compaction logic.

import ./message

const
  DefaultContextWindow* = 128_000
  DefaultCompactionThreshold* = 0.80
  MinMessagesToPreserve* = 4
  EstimatedTokensPerChar* = 0.25

type
  CompactionResult* = object
    history*: ConversationHistory
    tokensSaved*: int
    messagesBefore*: int
    messagesAfter*: int
    wasCompacted*: bool

  CompactionConfig* = object
    contextWindow*: int
    threshold*: float
    minPreserve*: int

func newCompactionConfig*(): CompactionConfig =
  CompactionConfig(
    contextWindow: DefaultContextWindow,
    threshold: DefaultCompactionThreshold,
    minPreserve: MinMessagesToPreserve,
  )

func estimateTokenCount*(history: ConversationHistory): int =
  var total = 0
  for msg in history:
    total += msg.text.len
    for tc in msg.toolCalls:
      total += tc.name.len + tc.inputJson.len
    total += msg.toolCallId.len
  total += history.len * 10
  int(float(total) * EstimatedTokensPerChar)

func needsCompaction*(history: ConversationHistory; cfg: CompactionConfig): bool =
  let tokens = estimateTokenCount(history)
  let thr = int(float(cfg.contextWindow) * cfg.threshold)
  tokens >= thr

func getSystemMessages*(history: ConversationHistory): ConversationHistory =
  result = @[]
  for msg in history:
    if msg.role == roleSystem:
      result.add(msg)

func getRecentMessages*(history: ConversationHistory; count: int): ConversationHistory =
  let start = max(0, history.len - count)
  result = @[]
  for i in start ..< history.len:
    result.add(history[i])

func createSummary*(msgs: ConversationHistory): string =
  if msgs.len <= 2:
    return ""
  
  var userPreviews: seq[string] = @[]
  var asstPreviews: seq[string] = @[]
  
  for msg in msgs:
    let preview = if msg.text.len > 80: msg.text[0..<80] & "..." else: msg.text
    if msg.role == roleUser:
      userPreviews.add(preview)
    elif msg.role == roleAssistant:
      asstPreviews.add(preview)
  
  var summary = "## Resumo da conversa anterior\n\n"
  
  if userPreviews.len > 0:
    summary &= "Topicos:\n"
    for i, p in userPreviews:
      summary &= "  " & $(i + 1) & ". " & p & "\n"
  
  if asstPreviews.len > 0:
    summary &= "\nRespostas:\n"
    for i, p in asstPreviews:
      summary &= "  " & $(i + 1) & ". " & p & "\n"
  
  summary

func compactHistory*(history: ConversationHistory; cfg: CompactionConfig): CompactionResult =
  let tokensBefore = estimateTokenCount(history)
  let thr = int(float(cfg.contextWindow) * cfg.threshold)
  
  if tokensBefore < thr:
    return CompactionResult(
      history: history,
      tokensSaved: 0,
      messagesBefore: history.len,
      messagesAfter: history.len,
      wasCompacted: false,
    )
  
  let systems = getSystemMessages(history)
  let recent = getRecentMessages(history, cfg.minPreserve)
  
  var older: ConversationHistory = @[]
  for msg in history:
    if msg.role != roleSystem:
      var isRecent = false
      for r in recent:
        if r.text == msg.text and r.role == msg.role:
          isRecent = true
          break
      if not isRecent:
        older.add(msg)
  
  let summary = createSummary(older)
  
  var newHistory: ConversationHistory = @[]
  for msg in systems:
    newHistory.add(msg)
  
  if summary.len > 0:
    newHistory.add(ChatMessage(role: roleUser, text: summary))
  
  for msg in recent:
    newHistory.add(msg)
  
  let tokensAfter = estimateTokenCount(newHistory)
  
  CompactionResult(
    history: newHistory,
    tokensSaved: tokensBefore - tokensAfter,
    messagesBefore: history.len,
    messagesAfter: newHistory.len,
    wasCompacted: true,
  )

func formatCompactionReport*(res: CompactionResult): string =
  if not res.wasCompacted:
    return "Contexto ainda dentro do limite. Nada a compactar."
  
  let savedTokens = res.tokensSaved
  let savedMsgs = res.messagesBefore - res.messagesAfter
  
  "Compaction:\n" &
  "- Tokens economizados: ~" & $savedTokens & "\n" &
  "- Mensagens removidas: " & $savedMsgs & "\n" &
  "- Historico: " & $res.messagesBefore & " -> " & $res.messagesAfter & " mensagens"
