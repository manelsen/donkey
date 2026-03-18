## Domain message types and pure orchestration helpers.
## No imports from adapters or ports — only stdlib and core/types.


import ../core/types

export types

# ── conversation roles ────────────────────────────────────────────────────────

const
  roleUser*      = "user"
  roleAssistant* = "assistant"
  roleSystem*    = "system"

# ── wire types ────────────────────────────────────────────────────────────────

type
  ChatMessage* = object
    role*:     string
    text*:     string
    imageUrl*: string        ## non-empty when message carries an image

  ConversationHistory* = seq[ChatMessage]

  InboundMessage* = object
    userId*:    UserId
    channelId*: string       ## channel-specific message id (for ack/dedup)
    text*:      string
    mediaUrl*:  string       ## non-empty when message has attachment
    channel*:   ChannelKind

  OutboundMessage* = object
    userId*:    UserId
    text*:      string
    replyTo*:   string       ## channel-specific id to reply to (optional)
    channel*:   ChannelKind
    streamId*:  string       ## non-empty for streaming turns
    isPartial*: bool         ## true for streaming partial edits
    mediaUrl*:  string       ## non-empty → send as photo/document instead of text

  ToolDescription* = object
    name*:        string
    description*: string
    schemaJson*:  string

  ToolCallRequest* = object
    id*:        string
    name*:      string
    inputJson*: string

  CompletionRequest* = object
    system*:    string
    messages*:  seq[ChatMessage]
    maxTokens*: int           ## 0 = provider default
    tools*:     seq[ToolDescription]

  CompletionResponse* = object
    text*:         string
    inputTokens*:  int
    outputTokens*: int
    toolCalls*:    seq[ToolCallRequest]

# ── history helpers ───────────────────────────────────────────────────────────

func newHistory*(): ConversationHistory = @[]

func addUser*(h: var ConversationHistory; text: string) =
  h.add ChatMessage(role: roleUser, text: text)

func addUserWithImage*(h: var ConversationHistory; text, imageUrl: string) =
  h.add ChatMessage(role: roleUser, text: text, imageUrl: imageUrl)

func addAssistant*(h: var ConversationHistory; text: string) =
  h.add ChatMessage(role: roleAssistant, text: text)

func addToolResult*(h: var ConversationHistory; id, name, output: string) =
  ## Appends a tool result message. The role "tool" identifies it downstream.
  h.add ChatMessage(role: "tool", text: output)

func trimTo*(h: var ConversationHistory; maxLen: int) =
  ## Keeps the most recent `maxLen` turns (discards oldest).
  if h.len > maxLen:
    h = h[h.len - maxLen .. ^1]

# ── pure orchestration ────────────────────────────────────────────────────────

func buildPrompt*(system: string;
                  history: ConversationHistory;
                  context: string): CompletionRequest =
  ## Assembles a CompletionRequest from parts. Pure: no I/O.
  let fullSystem =
    if context.len > 0: system & "\n\n## Memória relevante\n" & context
    else: system
  CompletionRequest(
    system:   fullSystem,
    messages: history,
  )

func buildPrompt*(system: string;
                  history: ConversationHistory;
                  context: string;
                  tools: seq[ToolDescription]): CompletionRequest =
  ## Assembles a CompletionRequest including tool descriptions. Pure: no I/O.
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
