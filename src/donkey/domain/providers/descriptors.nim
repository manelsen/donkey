## descriptors.nim — one table of provider identity.
##
## Every provider the runtime knows is described here: which transport speaks
## its wire format, which env names carry its credential, its base URL and
## default model, whether it is an aggregator, and its aliases.
##
## Pure data + pure lookup. No I/O, no network, no adapter imports.

import std/[options, strutils]
import ../../core/providers/provider_defaults

type
  ProviderTransport* = enum
    ptOpenAiChat        ## chat/completions OpenAI-compatible
    ptAnthropicMessages ## Anthropic Messages API
    ptGemini            ## Google generateContent
    ptOllama            ## native Ollama /api/chat
    ptMulti             ## a gateway that routes per model (Zen)

  ProviderAuthType* = enum
    atApiKey            ## static key from the env names below
    atNone              ## no credential (local endpoint)

  ProviderDescriptor* = object
    id*:           string
    transport*:    ProviderTransport
    authType*:     ProviderAuthType
    envNames*:     seq[string]   ## ordered fallbacks; first non-empty wins
    baseUrl*:      string
    baseUrlEnv*:   string        ## future per-provider endpoint override
    defaultModel*: string
    aliases*:      seq[string]
    aggregator*:   bool

const ProviderDescriptors*: seq[ProviderDescriptor] = @[
  ProviderDescriptor(
    id: "openrouter", transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["OPENROUTER_API_KEY"],
    baseUrl: "https://openrouter.ai/api/v1/chat/completions",
    defaultModel: DefaultModelOpenRouter, aggregator: true),
  ProviderDescriptor(
    id: "openai", transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["OPENAI_API_KEY"],
    baseUrl: "https://api.openai.com/v1/chat/completions",
    defaultModel: DefaultModelOpenAI),
  ProviderDescriptor(
    id: "deepseek", transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["DEEPSEEK_API_KEY"],
    baseUrl: "https://api.deepseek.com/v1/chat/completions",
    defaultModel: DefaultModelDeepSeek),
  ProviderDescriptor(
    id: "ollama", transport: ptOllama, authType: atNone,
    envNames: @["OLLAMA_BASE_URL"],
    baseUrl: "http://localhost:11434",
    defaultModel: DefaultModelOllama),
  ProviderDescriptor(
    id: "groq", transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["GROQ_API_KEY"],
    baseUrl: "https://api.groq.com/openai/v1/chat/completions",
    defaultModel: DefaultModelGroq),
  ProviderDescriptor(
    id: "opencode-go", transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["OPENCODE_API_KEY", "OPENCODE_GO_API_KEY"],
    baseUrl: "https://opencode.ai/zen/go/v1/chat/completions",
    defaultModel: DefaultModelOpenCodeGo, aliases: @["opencode"], aggregator: true),
  ProviderDescriptor(
    id: "zen", transport: ptMulti, authType: atApiKey,
    envNames: @["OPENCODE_API_KEY", "ZEN_API_KEY"],
    baseUrl: "https://opencode.ai/zen/v1/chat/completions",
    defaultModel: DefaultModelZen, aliases: @["opencode-zen"], aggregator: true),
  ProviderDescriptor(
    id: "anthropic", transport: ptAnthropicMessages, authType: atApiKey,
    envNames: @["ANTHROPIC_API_KEY"],
    baseUrl: "https://api.anthropic.com/v1/messages",
    defaultModel: DefaultModelAnthropic),
  ProviderDescriptor(
    id: "zai-anthropic", transport: ptAnthropicMessages, authType: atApiKey,
    envNames: @["ZAI_ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN",
                "ZAI_CODING_API_KEY", "ZAI_API_KEY", "ZHIPU_API_KEY"],
    baseUrl: "https://api.z.ai/api/anthropic",
    defaultModel: DefaultModelZai),
  ProviderDescriptor(
    id: "gemini", transport: ptGemini, authType: atApiKey,
    envNames: @["GEMINI_API_KEY"],
    baseUrl: "https://generativelanguage.googleapis.com/v1beta/models",
    defaultModel: DefaultModelGemini),
  ProviderDescriptor(
    id: "minimax", transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["MINIMAX_API_KEY"],
    baseUrl: "https://api.minimax.io/v1/chat/completions",
    defaultModel: DefaultModelMiniMax),
  ProviderDescriptor(
    id: "zai", transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["ZAI_API_KEY"],
    baseUrl: "https://api.z.ai/api/paas/v4/chat/completions",
    defaultModel: DefaultModelZai),
  ProviderDescriptor(
    id: "zai-coding", transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["ZAI_CODING_API_KEY", "ZHIPU_API_KEY"],
    baseUrl: "https://api.z.ai/api/coding/paas/v4/chat/completions",
    defaultModel: DefaultModelZai),
  ProviderDescriptor(
    id: "nvidia", transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["NVIDIA_API_KEY"],
    baseUrl: "https://integrate.api.nvidia.com/v1/chat/completions",
    baseUrlEnv: "NVIDIA_BASE_URL",
    defaultModel: DefaultModelNvidia,
    aliases: @["nvidia-nim", "nim", "build-nvidia"]),
  ProviderDescriptor(
    id: "alibaba", transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["DASHSCOPE_API_KEY"],
    baseUrl: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions",
    baseUrlEnv: "DASHSCOPE_BASE_URL",
    defaultModel: DefaultModelAlibaba,
    aliases: @["dashscope", "alibaba-cloud", "aliyun"]),
]

func providerDescriptors*(): seq[ProviderDescriptor] =
  ProviderDescriptors

func providerDescriptor*(id: string): Option[ProviderDescriptor] =
  ## Canonical id or alias; case-insensitive and trimmed, like the routing
  ## names.
  let key = id.strip.toLowerAscii()
  if key.len == 0:
    return none(ProviderDescriptor)
  for descriptor in ProviderDescriptors:
    if descriptor.id == key or key in descriptor.aliases:
      return some(descriptor)
  none(ProviderDescriptor)

func defaultProviderDescriptor*(): ProviderDescriptor =
  ## The fallback identity for unknown provider names: zai-coding.
  for descriptor in ProviderDescriptors:
    if descriptor.id == "zai-coding":
      return descriptor
  ProviderDescriptor(id: "zai-coding", transport: ptOpenAiChat,
                     authType: atApiKey,
                     envNames: @["ZAI_CODING_API_KEY", "ZHIPU_API_KEY"],
                     defaultModel: DefaultModelZai)

func descriptorOr*(id: string): ProviderDescriptor =
  providerDescriptor(id).get(defaultProviderDescriptor())
