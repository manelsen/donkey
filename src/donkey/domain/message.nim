## Domain message types and pure orchestration helpers.
## No imports from adapters or ports — only stdlib and core/types.

import std/strutils
import ../core/types

export types

# ── conversation roles ────────────────────────────────────────────────────────

const
  roleUser*      = "user"
  roleAssistant* = "assistant"
  roleSystem*    = "system"
  roleTool*      = "tool"   ## tool result turn (OpenAI convention)

# ── tool types (provider-agnostic) ────────────────────────────────────────────

type
  ToolDescription* = object
    ## Describes a tool for inclusion in a CompletionRequest.
    ## Adapter converts to provider-specific schema format.
    name*:        string
    description*: string
    schemaJson*:  string   ## JSON Schema for parameters (empty = any input)

  ToolCallRequest* = object
    ## A tool invocation requested by the provider in its response.
    id*:        string   ## correlation id (provider-assigned)
    name*:      string   ## tool name to call
    inputJson*: string   ## JSON-encoded arguments

# ── wire types ────────────────────────────────────────────────────────────────

type
  ChatMessage* = object
    role*:       string
    text*:       string
    imageUrl*:   string   ## non-empty: message carries an image (vision models)
    toolCallId*: string   ## non-empty: this is a tool result message
    toolName*:   string   ## tool name (needed by some providers for tool results)

  ConversationHistory* = seq[ChatMessage]

  InboundMessage* = object
    userId*:    UserId
    channel*:   ChannelKind  ## which adapter this arrived on
    channelId*: string       ## channel-specific message id (for ack/dedup)
    text*:      string
    mediaUrl*:  string       ## non-empty when message has attachment

  OutboundMessage* = object
    userId*:    UserId
    channel*:   ChannelKind  ## which adapter should deliver this
    text*:      string
    replyTo*:   string       ## channel-specific id to reply to (optional)
    streamId*:  string       ## non-empty: part of an SSE stream (for in-place editing)
    isPartial*: bool         ## true = more tokens coming; false = final chunk

  CompletionRequest* = object
    system*:    string
    messages*:  seq[ChatMessage]
    maxTokens*: int            ## 0 = provider default
    tools*:     seq[ToolDescription]  ## empty = no tool calling

  CompletionResponse* = object
    text*:         string
    inputTokens*:  int
    outputTokens*: int
    toolCalls*:    seq[ToolCallRequest]  ## non-empty when provider wants to call tools

# ── history helpers ───────────────────────────────────────────────────────────

func newHistory*(): ConversationHistory = @[]

func addUser*(h: var ConversationHistory; text: string) =
  h.add ChatMessage(role: roleUser, text: text)

func addUserWithImage*(h: var ConversationHistory; text, imageUrl: string) =
  ## Adds a user turn that carries an image attachment (for vision-capable models).
  h.add ChatMessage(role: roleUser, text: text, imageUrl: imageUrl)

func addAssistant*(h: var ConversationHistory; text: string) =
  h.add ChatMessage(role: roleAssistant, text: text)

func addToolResult*(h: var ConversationHistory;
                    callId:   string;
                    toolName: string;
                    output:   string) =
  ## Appends a tool result message (provider will see the tool's output).
  h.add ChatMessage(role: roleTool, text: output,
                    toolCallId: callId, toolName: toolName)

func trimTo*(h: var ConversationHistory; maxLen: int) =
  ## Keeps the most recent `maxLen` turns (discards oldest).
  if h.len > maxLen:
    h = h[h.len - maxLen .. ^1]

# ── pure orchestration ────────────────────────────────────────────────────────

func buildPrompt*(system:  string;
                  history: ConversationHistory;
                  context: string;
                  tools:   seq[ToolDescription] = @[]): CompletionRequest =
  ## Assembles a CompletionRequest from parts. Pure: no I/O.
  let fullSystem =
    if context.len > 0: system & "\n\n## Memória relevante\n" & context
    else: system
  CompletionRequest(
    system:   fullSystem,
    messages: history,
    tools:    tools,
  )

func needsOnboarding*(hasUserProfile: bool): bool =
  ## Pure decision: if there is no saved profile, run onboarding.
  not hasUserProfile

# ── message chunking ──────────────────────────────────────────────────────────

func splitChunks*(text: string; maxLen: int): seq[string] =
  ## Splits `text` into chunks of at most `maxLen` characters.
  ## Tries to split on "\n\n" (paragraphs), then "\n" (lines), then hard-cuts.
  ## No text is lost: join(result, "") == text.
  if text.len <= maxLen:
    return @[text]
  var pos = 0
  while pos < text.len:
    let remaining = text.len - pos
    if remaining <= maxLen:
      result.add(text[pos..^1])
      break
    ## Search for a good split point within the window.
    let window = text[pos ..< pos + maxLen]
    var cut = -1
    ## Try double newline (paragraph boundary).
    let pp = window.rfind("\n\n")
    if pp > 0: cut = pp + 2   ## keep the "\n\n" with the first chunk
    if cut < 0:
      ## Try single newline.
      let nl = window.rfind('\n')
      if nl > 0: cut = nl + 1   ## keep the "\n" with the first chunk
    if cut < 0 or cut == 0:
      cut = maxLen   ## hard cut
    result.add(text[pos ..< pos + cut])
    pos += cut
