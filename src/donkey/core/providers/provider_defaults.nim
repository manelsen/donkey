## provider_defaults.nim — default model ids shared by routing and descriptors.
##
## Core-level data only: no I/O, no imports from domain or adapters. The
## descriptor table (domain) and the routing defaults (core) read the same
## strings from here.

const
  DefaultModelOpenRouter*  = "openai/gpt-6.1-sol"
  DefaultModelOpenAI*      = "gpt-6.1-sol"
  DefaultModelDeepSeek*    = "deepseek-4.1-flash"
  DefaultModelOllama*      = "llama3.3"
  DefaultModelGroq*        = "llama-3.3-70b-versatile"
  DefaultModelOpenCodeGo*  = "opencode/deepseek-4.1-flash"
  DefaultModelZen*         = "zen/deepseek-4.1-flash"
  DefaultModelAnthropic*   = "claude-sonnet-5-5"
  DefaultModelZai*         = "glm-4.7"
  DefaultModelGemini*      = "gemini-3.8-flash"
  DefaultModelMiniMax*     = "MiniMax-M2"
