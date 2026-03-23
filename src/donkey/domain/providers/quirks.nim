## quirks — Pure normalization helpers for provider-specific message formatting.
##
## Each LLM provider has quirks in how it expects messages to be formatted:
## role names, history alternation, system prompt placement, tool call format.
## This module provides pure functions to normalize `ConversationHistory` or
## individual `ChatMessage` roles before they reach the adapter's `buildBody`.

import ../message

# ── Provider identifiers ───────────────────────────────────────────────────────

const
  ProviderGemini*    = "gemini"
  ProviderAnthropic* = "anthropic"
  ProviderOpenAI*    = "openai"
  ProviderOpenRouter* = "openrouter"
  ProviderZhipu*     = "zhipu"
  ProviderMiniMax*  = "minimax"
  ProviderOllama*   = "ollama"

# ── Role mapping ───────────────────────────────────────────────────────────────

func mapRoleForProvider*(role, provider: string): string =
  ## Maps an OpenAI-style role name to the provider's expected role name.
  case provider
  of ProviderGemini:
    if role == roleAssistant: "model"
    elif role == "tool": "user"
    else: role
  of ProviderAnthropic:
    ## Anthropic uses same role names as OpenAI (user/assistant/system/tool)
    role
  of ProviderOpenAI, ProviderOpenRouter, ProviderZhipu, ProviderMiniMax, ProviderOllama:
    role
  else:
    role

func mapRolesForProvider*(messages: seq[ChatMessage];
                          provider: string): seq[ChatMessage] =
  ## Maps all message roles in a ConversationHistory to the provider's expected names.
  for msg in messages:
    result.add ChatMessage(
      role:       mapRoleForProvider(msg.role, provider),
      text:       msg.text,
      imageUrl:   msg.imageUrl,
      toolCalls:  msg.toolCalls,
      toolCallId: msg.toolCallId,
    )

# ── History alternation (Gemini) ─────────────────────────────────────────────

func needsRoleAlternation*(provider: string): bool =
  ## Returns true if the provider requires strict user/model alternation in history.
  provider == ProviderGemini

func mergeAdjacentRoleMessages*(messages: seq[ChatMessage]): seq[ChatMessage] =
  ## Merges consecutive messages that have the same role by concatenating their text.
  ## Gemini requires alternating user/model turns; this normalizes the history.
  for msg in messages:
    if result.len > 0 and result[^1].role == msg.role:
      result[^1] = ChatMessage(
        role:       result[^1].role,
        text:       result[^1].text & "\n" & msg.text,
        imageUrl:   if msg.imageUrl.len > 0: msg.imageUrl else: result[^1].imageUrl,
        toolCalls:  result[^1].toolCalls & msg.toolCalls,
        toolCallId: result[^1].toolCallId,
      )
    else:
      result.add msg

func normalizeHistoryAlternation*(messages: seq[ChatMessage];
                                  provider: string): seq[ChatMessage] =
  ## If the provider requires role alternation, merges adjacent same-role messages.
  ## Identity function (returns copy) for providers that don't need alternation.
  if needsRoleAlternation(provider):
    mergeAdjacentRoleMessages(messages)
  else:
    messages

# ── Convenience normalizer ────────────────────────────────────────────────────

func normalizeForProvider*(messages: seq[ChatMessage];
                          provider: string): seq[ChatMessage] =
  ## Applies all relevant normalizations for a provider:
  ##   1. Role mapping
  ##   2. History alternation (if required)
  let step1 = normalizeHistoryAlternation(messages, provider)
  mapRolesForProvider(step1, provider)
