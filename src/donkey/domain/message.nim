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
    role*: string
    text*: string

  ConversationHistory* = seq[ChatMessage]

  InboundMessage* = object
    userId*:    UserId
    channelId*: string       ## channel-specific message id (for ack/dedup)
    text*:      string
    mediaUrl*:  string       ## non-empty when message has attachment

  OutboundMessage* = object
    userId*:    UserId
    text*:      string
    replyTo*:   string       ## channel-specific id to reply to (optional)

  CompletionRequest* = object
    system*:   string
    messages*: seq[ChatMessage]
    maxTokens*: int           ## 0 = provider default

  CompletionResponse* = object
    text*:      string
    inputTokens*:  int
    outputTokens*: int

# ── history helpers ───────────────────────────────────────────────────────────

func newHistory*(): ConversationHistory = @[]

func addUser*(h: var ConversationHistory; text: string) =
  h.add ChatMessage(role: roleUser, text: text)

func addAssistant*(h: var ConversationHistory; text: string) =
  h.add ChatMessage(role: roleAssistant, text: text)

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

func needsOnboarding*(hasUserProfile: bool): bool =
  ## Pure decision: if there is no saved profile, run onboarding.
  not hasUserProfile
