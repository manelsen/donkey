## AgentRunner — main loop for a single-agent session.
##
## Wires together: ChannelPort (recv/send) + MemoryPort (load/save) +
## ProviderPort (complete) + SecretStore.
##
## This module uses proc (effectful). The pure decisions live in domain/message.nim.

import std/strutils
import ../domain/message
import ../core/log
import ../core/pipeops
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
    memory*:     MdFileAdapter
    provider*:   ZhipuAdapter
    logger*:     Logger
    history*:    ConversationHistory
    maxHistory*: int

proc newAgentRunner*(memory: MdFileAdapter;
                     provider: ZhipuAdapter;
                     logger: Logger;
                     maxHistory = 20): AgentRunner =
  AgentRunner(memory: memory, provider: provider, logger: logger,
              history: newHistory(), maxHistory: maxHistory)

proc runOnboardingTurn*(runner: var AgentRunner;
                        userId: UserId;
                        userText: string): Result[string, string] =
  runner.history.addUser(userText)
  runner.history.trimTo(runner.maxHistory)

  let resp = ? runner.provider.complete(buildPrompt(OnboardingSystem, runner.history, ""))

  runner.history.addAssistant(resp.text)
  runner.logger.info("onboarding turn tokens_in=" & $resp.inputTokens &
                     " tokens_out=" & $resp.outputTokens)

  let parsed = parseOnboardingResponse(resp.text)
  if parsed.complete:
    runner.memory.saveUserMd(userId,
      bootstrapUserMd(parsed.name, parsed.callMe, parsed.tz, parsed.lang))
    runner.logger.info("onboarding complete user=" & $userId)

  ok(resp.text)

proc runTurn*(runner: var AgentRunner;
              userId: UserId;
              userText: string): Result[string, string] =
  let ctx = runner.memory.loadContext(userId)
  runner.history.addUser(userText)
  runner.history.trimTo(runner.maxHistory)

  let context = (ctx.memoryMd & "\n" & ctx.preferencesMd).strip()
  let resp    = ? runner.provider.complete(
                    buildPrompt(DefaultSystem, runner.history, context))

  runner.history.addAssistant(resp.text)
  runner.logger.info("turn complete user=" & $userId &
                     " tokens_in=" & $resp.inputTokens &
                     " tokens_out=" & $resp.outputTokens)
  ok(resp.text)
