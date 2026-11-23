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
  DefaultModelNvidia*      = "nvidia/nemotron-3.5-super-vl-120b-a12b"
  DefaultModelAlibaba*     = "qwen3.8-max"  ## first of the curated DashScope list
  DefaultModelFireworks*   = "accounts/fireworks/models/kimi-k2p6"
    ## Donkey's choice, not a Hermes default: this is
    ## `fallback_models[0]` in the Fireworks profile
    ## (`plugins/model-providers/fireworks/__init__.py:43-45`). Hermes'
    ## `default_aux_model` is `accounts/fireworks/models/glm-5p2`.
