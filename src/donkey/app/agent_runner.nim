## AgentRunner — main loop for a single-agent session.
##
## Wires together: ChannelPort (recv/send) + MemoryPort (load/save) +
## ProviderPort (complete) + SecretStore.
##
## Bootstrapping flow:
##   1. Receive inbound message.
##   2. If no user profile → run onboarding conversation (collect name/callMe/tz/lang).
##   3. Load context (USER.md + MEMORY.md + PREFERENCES.md).
##   4. Build prompt (system + history + context).
##   5. Call provider.complete().
##   6. Append user+assistant turns to history.
##   7. Send outbound message.
##   8. Persist updated memory.
##
## This module uses proc (effectful). The pure decisions live in domain/message.nim.

import std/strutils
import ../domain/message
import ../core/log
import ../adapters/memory/md_file
import ../adapters/provider/zhipu

# ── System prompts ─────────────────────────────────────────────────────────────

const
  OnboardingSystem* = """You are Donkey, a friendly AI assistant. A new user just connected.
Your task is to collect their basic information through a natural conversation.
Ask for: their full name, what they'd like to be called, their timezone, and preferred language.
Ask one or two things at a time. When you have all four, end your response with exactly:
  ONBOARDING_COMPLETE: name=<name>|callMe=<callMe>|tz=<tz>|lang=<lang>
where each value is on one line with no extra spaces."""

  DefaultSystem* = """You are Donkey, a personal AI assistant.
Be concise, helpful, and remember what the user tells you.
Respond in the user's preferred language."""

# ── Onboarding parser ──────────────────────────────────────────────────────────

type
  OnboardingResult* = object
    complete*: bool
    name*:     string
    callMe*:   string
    tz*:       string
    lang*:     string

func parseOnboardingResponse*(text: string): OnboardingResult =
  ## Extracts onboarding fields from LLM response. Pure func.
  ## Looks for: ONBOARDING_COMPLETE: name=X|callMe=Y|tz=Z|lang=W
  for line in text.splitLines():
    let stripped = line.strip()
    if not stripped.startsWith("ONBOARDING_COMPLETE:"):
      continue
    let payload = stripped[len("ONBOARDING_COMPLETE:") ..^ 1].strip()
    result.complete = true
    for part in payload.split('|'):
      let kv = part.split('=', 1)
      if kv.len < 2: continue
      case kv[0].strip()
      of "name":   result.name   = kv[1].strip()
      of "callMe": result.callMe = kv[1].strip()
      of "tz":     result.tz     = kv[1].strip()
      of "lang":   result.lang   = kv[1].strip()
    return
  result.complete = false

# ── AgentRunner ────────────────────────────────────────────────────────────────

type
  AgentRunner* = object
    memory*:   MdFileAdapter
    provider*: ZhipuAdapter
    logger*:   Logger
    history*:  ConversationHistory
    maxHistory*: int   ## max turns kept in memory (default 20)

proc newAgentRunner*(memory: MdFileAdapter;
                     provider: ZhipuAdapter;
                     logger: Logger;
                     maxHistory = 20): AgentRunner =
  AgentRunner(
    memory:     memory,
    provider:   provider,
    logger:     logger,
    history:    newHistory(),
    maxHistory: maxHistory,
  )

proc runOnboardingTurn*(runner: var AgentRunner;
                        userId: UserId;
                        userText: string): tuple[reply: string; done: bool] =
  ## Runs one turn of the onboarding conversation.
  ## Returns the assistant's reply and whether onboarding is complete.
  runner.history.addUser(userText)
  runner.history.trimTo(runner.maxHistory)

  let req  = buildPrompt(OnboardingSystem, runner.history, "")
  let resp = runner.provider.complete(req)

  runner.history.addAssistant(resp.text)
  runner.logger.info("onboarding turn tokens_in=" & $resp.inputTokens &
                     " tokens_out=" & $resp.outputTokens)

  let parsed = parseOnboardingResponse(resp.text)
  if parsed.complete:
    let userMd = bootstrapUserMd(parsed.name, parsed.callMe, parsed.tz, parsed.lang)
    runner.memory.saveUserMd(userId, userMd)
    runner.logger.info("onboarding complete user=" & $userId)
    return (resp.text, true)

  return (resp.text, false)

proc runTurn*(runner: var AgentRunner;
              userId: UserId;
              userText: string): string =
  ## Runs one normal conversation turn.
  ## Returns the assistant's reply text.
  let ctx = runner.memory.loadContext(userId)

  runner.history.addUser(userText)
  runner.history.trimTo(runner.maxHistory)

  let system  = DefaultSystem
  let context = ctx.memoryMd & "\n" & ctx.preferencesMd
  let req     = buildPrompt(system, runner.history, context.strip())
  let resp    = runner.provider.complete(req)

  runner.history.addAssistant(resp.text)
  runner.logger.info("turn complete user=" & $userId &
                     " tokens_in=" & $resp.inputTokens &
                     " tokens_out=" & $resp.outputTokens)

  result = resp.text
