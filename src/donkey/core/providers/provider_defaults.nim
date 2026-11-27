## provider_defaults.nim — default model ids shared by routing and descriptors.
##
## Core-level data only: no I/O, no imports from domain or adapters. The
## descriptor table (domain) and the routing defaults (core) read the same
## strings from here.

const
  DefaultModelOpenRouter*  = "openai/gpt-6.1-sol"
  DefaultModelOpenAI*      = "gpt-6.2-sol"
  DefaultModelDeepSeek*    = "deepseek-flash"   ## V4.1 Flash; `deepseek-4.1-flash` is not an API id
  DefaultModelOllama*      = "llama3.3"
  DefaultModelGroq*        = "openai/gpt-oss-120b"   ## Llama 3.x shut down for free and developer tiers on 2026-08-16
  DefaultModelOpenCodeGo*  = "opencode/deepseek-4.1-flash"
  DefaultModelZen*         = "zen/deepseek-4.1-flash"
  DefaultModelAnthropic*   = "claude-sonnet-5-5"
  DefaultModelZai*         = "glm-4.7"
  DefaultModelGemini*      = "gemini-4-hydrogen"
  DefaultModelMiniMax*     = "MiniMax-M3.1-Flash"
  DefaultModelNvidia*      = "nvidia/nemotron-3.5-super-vl-120b-a12b"
  DefaultModelMistral*     = "mistral-large-latest"
  DefaultModelBedrock*     = "amazon.nova-pro-v1:0"
    ## AWS's own model: on-demand in us-east-1, tools and images, no
    ## third-party model access form to fill in.
    ## Mistral's own moving alias for its flagship chat model.
  DefaultModelAlibaba*     = "qwen3.8-max"  ## first of the curated DashScope list
  DefaultModelAzure*       = "gpt-4.1"
    ## On Azure the model is the operator's deployment name; this is only a
    ## common one. Set the deployment in the preferences (`model = ...`).
  DefaultModelFireworks*   = "accounts/fireworks/models/kimi-k2p6"
    ## Donkey's choice, not a Hermes default: this is
    ## `fallback_models[0]` in the Fireworks profile
    ## (`plugins/model-providers/fireworks/__init__.py:43-45`). Hermes'
    ## `default_aux_model` is `accounts/fireworks/models/glm-5p2`.
