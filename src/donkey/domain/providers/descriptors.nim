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
    ptBedrockConverse   ## AWS Bedrock Converse (SigV4 or Bedrock API key)

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
    streamsToolCalls*: bool      ## its stream assembles tool calls, so the
                                 ## tool loop may stream through it with
                                 ## tools on (checked against the runtime
                                 ## builder by t_stream_capability)

const ProviderDescriptors*: seq[ProviderDescriptor] = @[
  ProviderDescriptor(
    id: "openrouter", streamsToolCalls: true, transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["OPENROUTER_API_KEY"],
    baseUrl: "https://openrouter.ai/api/v1/chat/completions",
    defaultModel: DefaultModelOpenRouter, aggregator: true),
  ProviderDescriptor(
    id: "openai", streamsToolCalls: true, transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["OPENAI_API_KEY"],
    baseUrl: "https://api.openai.com/v1/chat/completions",
    defaultModel: DefaultModelOpenAI),
  ProviderDescriptor(
    id: "deepseek", streamsToolCalls: true, transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["DEEPSEEK_API_KEY"],
    baseUrl: "https://api.deepseek.com/v1/chat/completions",
    defaultModel: DefaultModelDeepSeek),
  ProviderDescriptor(
    id: "ollama", transport: ptOllama, authType: atNone,
    envNames: @["OLLAMA_BASE_URL"],
    baseUrl: "http://localhost:11434",
    defaultModel: DefaultModelOllama),
  ProviderDescriptor(
    id: "groq", streamsToolCalls: true, transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["GROQ_API_KEY"],
    baseUrl: "https://api.groq.com/openai/v1/chat/completions",
    defaultModel: DefaultModelGroq),
  ProviderDescriptor(
    id: "opencode-go", streamsToolCalls: true, transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["OPENCODE_API_KEY", "OPENCODE_GO_API_KEY"],
    baseUrl: "https://opencode.ai/zen/go/v1/chat/completions",
    defaultModel: DefaultModelOpenCodeGo, aliases: @["opencode"], aggregator: true),
  ProviderDescriptor(
    id: "zen", streamsToolCalls: true, transport: ptMulti, authType: atApiKey,
    envNames: @["OPENCODE_API_KEY", "ZEN_API_KEY"],
    baseUrl: "https://opencode.ai/zen/v1/chat/completions",
    defaultModel: DefaultModelZen, aliases: @["opencode-zen"], aggregator: true),
  ProviderDescriptor(
    id: "anthropic", streamsToolCalls: true, transport: ptAnthropicMessages, authType: atApiKey,
    envNames: @["ANTHROPIC_API_KEY"],
    baseUrl: "https://api.anthropic.com/v1/messages",
    defaultModel: DefaultModelAnthropic),
  ProviderDescriptor(
    id: "zai-anthropic", streamsToolCalls: true, transport: ptAnthropicMessages, authType: atApiKey,
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
    id: "nvidia", streamsToolCalls: true, transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["NVIDIA_API_KEY"],
    baseUrl: "https://integrate.api.nvidia.com/v1/chat/completions",
    baseUrlEnv: "NVIDIA_BASE_URL",
    defaultModel: DefaultModelNvidia,
    aliases: @["nvidia-nim", "nim", "build-nvidia"]),
  ProviderDescriptor(
    id: "alibaba", streamsToolCalls: true, transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["DASHSCOPE_API_KEY"],
    baseUrl: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions",
    baseUrlEnv: "DASHSCOPE_BASE_URL",
    defaultModel: DefaultModelAlibaba,
    aliases: @["dashscope", "alibaba-cloud", "aliyun"]),
  ProviderDescriptor(
    id: "fireworks", streamsToolCalls: true, transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["FIREWORKS_API_KEY"],
    baseUrl: "https://api.fireworks.ai/inference/v1/chat/completions",
    baseUrlEnv: "",
    defaultModel: DefaultModelFireworks,
    aliases: @["fireworks-ai", "fw"]),
  ProviderDescriptor(
    id: "mistral", streamsToolCalls: true, transport: ptOpenAiChat, authType: atApiKey,
    envNames: @["MISTRAL_API_KEY"],
    baseUrl: "https://api.mistral.ai/v1/chat/completions",
    baseUrlEnv: "MISTRAL_BASE_URL",
    defaultModel: DefaultModelMistral,
    aliases: @["mistralai", "mistral-ai"]),
  ProviderDescriptor(
    ## Converse API. The bearer is a Bedrock API key; IAM credentials
    ## (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN) are read
    ## separately into the spec, and the region from AWS_REGION.
    id: "bedrock", transport: ptBedrockConverse, authType: atApiKey,
    envNames: @["AWS_BEARER_TOKEN_BEDROCK"],
    baseUrl: "https://bedrock-runtime.us-east-1.amazonaws.com",
    baseUrlEnv: "BEDROCK_BASE_URL",
    defaultModel: DefaultModelBedrock,
    aliases: @["aws-bedrock", "amazon-bedrock", "aws"]),
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

func streamsToolCalls*(id: string): bool =
  ## Whether the tool loop may stream through this provider with tools on.
  ## An unknown name does not.
  let descriptor = providerDescriptor(id)
  descriptor.isSome and descriptor.get.streamsToolCalls
