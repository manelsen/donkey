import std/unittest
import donkey/core/memory_rerank_prefs

suite "memory_rerank_prefs":

  test "normalize accepts known aliases":
    check normalizeMemoryRerankMode("off") == MemoryRerankOff
    check normalizeMemoryRerankMode("fixed") == MemoryRerankExplicit
    check normalizeMemoryRerankMode("follow-chat") == MemoryRerankDialogue

  test "parse reads explicit rerank preferences":
    let prefs = parseMemoryRerankPrefs("""
memory_rerank_mode = "explicit"
memory_rerank_provider = "openrouter"
memory_rerank_model = "qwen/qwen3-32b"
""")
    check prefs.mode == MemoryRerankExplicit
    check prefs.provider == "openrouter"
    check prefs.model == "qwen/qwen3-32b"

  test "parse accepts shorthand memory_rerank alias":
    let prefs = parseMemoryRerankPrefs("""
memory_rerank = "dialogue"
""")
    check prefs.mode == MemoryRerankDialogue
