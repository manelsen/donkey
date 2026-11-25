## mcp_sampling_pure — MCP sampling, the pure half (PRD-roadmap E5.1, E5.3).
##
## A server may ask the client to run its model (`sampling/createMessage`,
## MCP 2024-11-05). The request is read (text only), turned into a model
## request without tools and with a capped token limit, answered in MCP's
## shape, summarised for the person who must approve it, and counted against
## a daily token cap per server. A server is known by its command and
## arguments: a permanent approval follows what runs, not a name.
##
## `proc` where JSON is built or parsed (ADR-007 allows it).

import std/[hashes, json, strutils, tables]
import ../../core/pipeops
import ../message

const
  SummaryQuoteChars* = 300
  DayMs = 86_400_000'i64

type
  SamplingMessage* = object
    role*: string   ## user or assistant
    text*: string

  SamplingRequest* = object
    messages*:     seq[SamplingMessage]
    systemPrompt*: string
    maxTokens*:    int

  SamplingBudget* = object
    dailyCap*: int
    spent:     Table[string, (int64, int)]   ## server → (day, tokens)

proc parseSamplingRequest*(params: JsonNode): Result[SamplingRequest, string] =
  if params.isNil or params.kind != JObject:
    return err("sampling request without parameters")
  let msgs = params{"messages"}
  if msgs.isNil or msgs.kind != JArray or msgs.len == 0:
    return err("sampling request without messages")
  var r = SamplingRequest(systemPrompt: params{"systemPrompt"}.getStr,
                          maxTokens: params{"maxTokens"}.getInt(0))
  for m in msgs:
    let role = m{"role"}.getStr
    if role notin ["user", "assistant"]:
      return err("sampling message role must be user or assistant")
    let content = m{"content"}
    if content.isNil or content{"type"}.getStr != "text":
      return err("only text content can be sampled")
    r.messages.add SamplingMessage(role: role, text: content{"text"}.getStr)
  if r.maxTokens <= 0:
    return err("sampling request without maxTokens")
  ok(r)

func toCompletionRequest*(r: SamplingRequest; maxTokensCap: int): CompletionRequest =
  ## No tools: the server gets text back, never actions.
  var h = newHistory()
  for m in r.messages:
    if m.role == "user": h.addUser(m.text) else: h.addAssistant(m.text)
  CompletionRequest(system: r.systemPrompt, messages: h,
                    maxTokens: min(r.maxTokens, maxTokensCap))

proc samplingResult*(text, model: string): JsonNode =
  %* {"role": "assistant", "content": {"type": "text", "text": text},
      "model": model, "stopReason": "endTurn"}

func clip(s: string; n: int): string =
  let flat = s.replace('\n', ' ').strip
  if flat.len <= n: flat else: flat[0 ..< n] & "…"

func approvalSummary*(serverName: string; r: SamplingRequest): string =
  ## What the person reads before saying yes: who asks, what it asks the
  ## model, and how much it may spend.
  var lastUser = ""
  for m in r.messages:
    if m.role == "user": lastUser = m.text
  "O servidor MCP «" & serverName & "» quer usar o seu modelo (até " &
    $r.maxTokens & " tokens): «" & clip(lastUser, SummaryQuoteChars) & "»"

func serverIdentity*(command: string; args: openArray[string]): string =
  ## What runs, not what it is called.
  var parts = @[command]
  for a in args: parts.add a
  let joined = parts.join("\x1f")
  joined.strip.toLowerAscii & "#" & toHex(hash(joined).uint64)

func samplingApprovalKey*(identity: string): string =
  "sampling:" & toHex(hash(identity).uint64)

func allows*(b: SamplingBudget; server: string; tokens: int; dayMs: int64): bool =
  if b.dailyCap <= 0:
    return true
  let day = dayMs div DayMs
  let (d, used) = b.spent.getOrDefault(server, (-1'i64, 0))
  let today = if d == day: used else: 0
  today + tokens <= b.dailyCap

func spend*(b: var SamplingBudget; server: string; tokens: int; dayMs: int64) =
  let day = dayMs div DayMs
  let (d, used) = b.spent.getOrDefault(server, (-1'i64, 0))
  b.spent[server] = (day, (if d == day: used else: 0) + tokens)
