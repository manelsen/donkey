import std/[strutils, unittest]
import donkey/domain/compaction_pure
import donkey/domain/message

proc runTests*() =
  suite "Compaction Pure":

    test "estimateTokenCount returns zero for empty":
      let emptyHistory: ConversationHistory = @[]
      check estimateTokenCount(emptyHistory) == 0

    test "estimateTokenCount counts messages":
      var history: ConversationHistory = @[]
      history.add(ChatMessage(role: roleUser, text: "Hello"))
      history.add(ChatMessage(role: roleAssistant, text: "Hi there!"))
      let tokens = estimateTokenCount(history)
      check tokens > 0

    test "needsCompaction returns false for small history":
      let config = newCompactionConfig()
      var history: ConversationHistory = @[]
      history.add(ChatMessage(role: roleUser, text: "Hi"))
      check needsCompaction(history, config) == false

    test "getSystemMessages filters correctly":
      var history: ConversationHistory = @[]
      history.add(ChatMessage(role: roleSystem, text: "You are helpful"))
      history.add(ChatMessage(role: roleUser, text: "Hello"))
      history.add(ChatMessage(role: roleAssistant, text: "Hi"))
      history.add(ChatMessage(role: roleSystem, text: "System prompt"))
      let systems = getSystemMessages(history)
      check systems.len == 2

    test "getRecentMessages gets last N":
      var history: ConversationHistory = @[]
      for i in 1..10:
        history.add(ChatMessage(role: roleUser, text: "Message " & $i))
      let recent = getRecentMessages(history, 3)
      check recent.len == 3
      check recent[0].text == "Message 8"
      check recent[1].text == "Message 9"
      check recent[2].text == "Message 10"

    test "compactHistory preserves system messages":
      var config = newCompactionConfig()
      config.contextWindow = 1000
      config.threshold = 0.1
      var history: ConversationHistory = @[]
      history.add(ChatMessage(role: roleSystem, text: "You are an assistant"))
      history.add(ChatMessage(role: roleUser, text: "Hello"))
      history.add(ChatMessage(role: roleAssistant, text: "Hi"))
      let result = compactHistory(history, config)
      check result.history.len >= 1
      check result.history[0].role == roleSystem

    test "compactHistory returns has wasCompacted flag":
      var config = newCompactionConfig()
      config.contextWindow = 100000
      config.threshold = 0.9
      var history: ConversationHistory = @[]
      history.add(ChatMessage(role: roleUser, text: "Short message"))
      let result = compactHistory(history, config)
      check result.wasCompacted == false

    test "compactHistory returns unchanged when under threshold":
      var config = newCompactionConfig()
      config.contextWindow = 100000
      config.threshold = 0.9
      var history: ConversationHistory = @[]
      history.add(ChatMessage(role: roleUser, text: "Short message"))
      let result = compactHistory(history, config)
      check result.messagesBefore == result.messagesAfter

    test "formatCompactionReport for no compaction":
      let noCompact = CompactionResult(
        history: @[],
        tokensSaved: 0,
        messagesBefore: 5,
        messagesAfter: 5,
        wasCompacted: false,
      )
      check formatCompactionReport(noCompact) == "Contexto ainda dentro do limite. Nada a compactar."

    test "formatCompactionReport for compacted":
      let compacted = CompactionResult(
        history: @[],
        tokensSaved: 5000,
        messagesBefore: 20,
        messagesAfter: 8,
        wasCompacted: true,
      )
      let report = formatCompactionReport(compacted)
      check report.len > 10

    test "compactHistory marks its summary as synthetic and keeps recent numbers":
      var h: ConversationHistory
      for i in 1 .. 40:
        h.add(ChatMessage(role: (if i mod 2 == 1: roleUser else: roleAssistant),
                          text: "mensagem " & $i & " " & repeat("x", 400),
                          seq: i.int64))
      var cfg = newCompactionConfig()
      cfg.contextWindow = 1000
      cfg.threshold = 0.1
      let res = compactHistory(h, cfg)
      check res.wasCompacted
      var synthetic = 0
      for msg in res.history:
        if msg.seq == SyntheticMessageSeq:
          inc synthetic
        else:
          check msg.seq > 0
      check synthetic == 1
      check res.history[^1].seq == 40

when isMainModule:
  runTests()
