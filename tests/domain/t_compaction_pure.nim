import std/unittest
import donkey/domain/compaction_pure
import donkey/domain/message

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
