## AgentRunner — main loop for a single-agent session.
##
## Wires together: ChannelPort (recv/send) + MemoryPort (load/save) +
## ProviderPort (complete) + ToolPort (invoke).
##
## This module uses proc (effectful). The pure decisions live in domain/message.nim.

import std/[json, strutils]
import ../domain/message
import ../core/log
import ../core/pipeops
import ../adapters/memory/md_file
import ../adapters/tool/mcp_client
import ../ports/provider
import ../ports/tool

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

  MaxToolRounds* = 5   ## safety limit on tool call loops

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
    let stripped = line |> strip
    if not stripped.startsWith("ONBOARDING_COMPLETE:"):
      continue
    let payload = stripped[len("ONBOARDING_COMPLETE:") ..^ 1] |> strip
    result.complete = true
    for part in payload.split('|'):
      let kv = part.split('=', 1)
      if kv.len < 2: continue
      case kv[0] |> strip
      of "name":   result.name   = kv[1] |> strip
      of "callMe": result.callMe = kv[1] |> strip
      of "tz":     result.tz     = kv[1] |> strip
      of "lang":   result.lang   = kv[1] |> strip
    return
  result.complete = false

# ── Tool helpers ────────────────────────────────────────────────────────────────

func buildToolsSystemSuffix*(tools: seq[ToolDescription]): string =
  ## Pure func. Appends a tool list to the system prompt when tools are available.
  if tools.len == 0:
    return ""
  result = "\n\n## Available tools\n"
  for td in tools:
    result.add("- **" & td.name & "**: " & td.description & "\n")

func extractText*(resp: CompletionResponse): Result[string, string] =
  ## Lifts CompletionResponse.text into Result, treating empty as error.
  ## Used in >>= chains: complete >>= extractText.
  if resp.text.len > 0: ok(resp.text)
  else: err("empty LLM response")

proc executeToolCalls*(clients: var seq[McpClientAdapter];
                       calls:   seq[ToolCallRequest];
                       logger:  Logger): seq[(ToolCallRequest, string)] =
  ## Executes all tool calls. Returns (call, output) pairs.
  for tc in calls:
    let input =
      try: parseJson(tc.inputJson)
      except: newJObject()
    let call = ToolCall(id: tc.id, name: tc.name, input: input)

    var invoked = false
    for i in 0 ..< clients.len:
      # Try each client in order; stop at first that knows this tool.
      let res = clients[i].invoke(call)
      if res.isOk:
        result.add((tc, res.value.output))
        invoked = true
        break
      # If the client returned an error, continue to next client.

    if not invoked:
      logger.warn("tool not found: " & tc.name)
      result.add((tc, "Tool '" & tc.name & "' not found."))

# ── AgentRunner ────────────────────────────────────────────────────────────────

type
  AgentRunner* = object
    memory*:     MdFileAdapter
    complete*:   CompleteFn
    clients*:    seq[McpClientAdapter]  ## registered tool servers
    tools*:      seq[ToolDescription]   ## cached tool schemas
    logger*:     Logger
    history*:    ConversationHistory
    maxHistory*: int

proc newAgentRunner*(memory:    MdFileAdapter;
                     complete:  CompleteFn;
                     logger:    Logger;
                     clients:   seq[McpClientAdapter] = @[];
                     maxHistory = 20): AgentRunner =
  ## Load tool schemas from all registered clients.
  var tools:     seq[ToolDescription]
  var liveClients: seq[McpClientAdapter] = clients

  for i in 0 ..< liveClients.len:
    let schemasRes = liveClients[i].listTools()
    if schemasRes.isOk:
      for s in schemasRes.value:
        tools.add(ToolDescription(
          name:        s.name,
          description: s.description,
          schemaJson:  if s.inputSchema != nil: $s.inputSchema else: "",
        ))
    else:
      logger.warn("listTools failed for client " & $i & ": " & schemasRes.error)

  AgentRunner(memory: memory, complete: complete, clients: liveClients,
              tools: tools, logger: logger,
              history: newHistory(), maxHistory: maxHistory)

proc runOnboardingTurn*(runner: var AgentRunner;
                        userId: UserId;
                        userText: string): Result[string, string] =
  runner.history.addUser(userText)
  runner.history.trimTo(runner.maxHistory)

  let resp = ? (buildPrompt(OnboardingSystem, runner.history, "") |> runner.complete)

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

  let context     = (ctx.memoryMd & "\n" & ctx.preferencesMd) |> strip
  let toolsSuffix = runner.tools |> buildToolsSystemSuffix
  let system      = DefaultSystem & toolsSuffix

  var round = 0
  while round < MaxToolRounds:
    inc round
    let resp = ? (buildPrompt(system, runner.history, context, runner.tools) |> runner.complete)

    if resp.toolCalls.len == 0:
      ## Final text response — record and return.
      if resp.text.len > 0:
        runner.history.addAssistant(resp.text)
      runner.logger.info("turn complete user=" & $userId &
                         " round=" & $round &
                         " tokens_in=" & $resp.inputTokens &
                         " tokens_out=" & $resp.outputTokens)
      return ok(resp.text)

    ## Tool call round — execute and feed results back.
    runner.logger.info("tool calls=" & $resp.toolCalls.len & " round=" & $round)
    let results = executeToolCalls(runner.clients, resp.toolCalls, runner.logger)
    for (tc, output) in results:
      runner.history.addToolResult(tc.id, tc.name, output)

  ## Exceeded MaxToolRounds — return last assistant text if any.
  err("Tool call loop exceeded " & $MaxToolRounds & " rounds")
