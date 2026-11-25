## named_agent_pure.nim — a user's named agents, the pure part.
##
## A named agent is a persona the user keeps in their paddock
## (`agents/<name>.toml`): a name, a description that is its persona and role,
## and optionally a provider and model. `@name` at the start of a message makes
## that turn the agent's. Memory is the user's (USER.md, MEMORY.md, the graph)
## and the conversation is shared; the agent adds only its own notes
## (`agents/<name>.notes.md`).
##
## The file is a small TOML subset — `key = "basic string"` lines and `#`
## comments — read here so the domain needs no TOML library.

import std/[options, strutils]
import ../../core/pipeops
import ../message
import ../builtin_tools
import ../more_tools

const MaxAgentNameLen* = 32

type
  NamedAgent* = object
    name*:        string
    description*: string
    provider*:    string   ## "" = the user's routing
    model*:       string   ## "" = the provider's default

  AgentMention* = object
    name*: string   ## lower case
    text*: string   ## the message without the mention

func validAgentName*(name: string): bool =
  ## Lower-case letters, digits and '-', up to 32: safe as a file name.
  name.len in 1 .. MaxAgentNameLen and
    name.allCharsInSet({'a' .. 'z', '0' .. '9', '-'})

func agentFileName*(name: string): string = name & ".toml"
func agentNotesFileName*(name: string): string = name & ".notes.md"

func tomlBasic(value: string): string =
  result = "\""
  for c in value:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    of '\t': result.add("\\t")
    of '\r': result.add("\\r")
    else: result.add(c)
  result.add('"')

func unquote(raw: string): Result[string, string] =
  let v = raw.strip
  if v.len < 2 or v[0] != '"' or v[^1] != '"':
    return err("expected a quoted string: " & raw)
  var output = ""
  var i = 1
  while i < v.len - 1:
    if v[i] == '\\' and i + 1 < v.len - 1:
      case v[i + 1]
      of 'n': output.add('\n')
      of 't': output.add('\t')
      of 'r': output.add('\r')
      of '"': output.add('"')
      of '\\': output.add('\\')
      else: output.add(v[i + 1])
      i += 2
    else:
      output.add(v[i])
      inc i
  ok(output)

func parseAgentFile*(text: string): Result[NamedAgent, string] =
  var agent = NamedAgent()
  for raw in text.splitLines:
    let line = raw.strip
    if line.len == 0 or line.startsWith("#"): continue
    let eq = line.find('=')
    if eq <= 0: return err("not a `key = \"value\"` line: " & line)
    let key = line[0 ..< eq].strip
    let value = ? unquote(line[eq + 1 .. ^1])
    case key
    of "name": agent.name = value
    of "description": agent.description = value
    of "provider": agent.provider = value
    of "model": agent.model = value
    else: discard   ## unknown keys are left for later versions
  if not validAgentName(agent.name):
    return err("agent name must be 1-32 of a-z, 0-9 and '-': " & agent.name)
  if agent.description.strip.len == 0:
    return err("agent " & agent.name & " has no description")
  ok(agent)

func renderAgentFile*(a: NamedAgent): string =
  result = "name = " & tomlBasic(a.name) & "\n" &
           "description = " & tomlBasic(a.description) & "\n"
  if a.provider.len > 0:
    result.add("provider = " & tomlBasic(a.provider) & "\n")
  if a.model.len > 0:
    result.add("model = " & tomlBasic(a.model) & "\n")

func agentMention*(text: string): Option[AgentMention] =
  ## `@name` as the first word calls that agent; the name ends at the first
  ## character that cannot be in one (space, punctuation).
  let t = text.strip(trailing = false)
  if t.len < 2 or t[0] != '@': return none(AgentMention)
  var i = 1
  while i < t.len and t[i].toLowerAscii in {'a' .. 'z', '0' .. '9', '-'}:
    inc i
  let name = t[1 ..< i].toLowerAscii
  if not validAgentName(name): return none(AgentMention)
  var rest = t[i .. ^1]
  if rest.len > 0 and rest[0] in {',', ':', ';'}:
    rest = rest[1 .. ^1]
  some(AgentMention(name: name, text: rest.strip))

func namedAgentSystem*(a: NamedAgent; notes, toolsSuffix: string): string =
  ## The system prompt of the agent's turn: its persona instead of the user's
  ## main assistant, the shared memory still arriving as context.
  result = "You are " & a.name & ", one of the user's named agents. " &
           "The user called you by name for this message.\n\n" &
           "## Your role\n" & a.description.strip & "\n\n" &
           "You share the user's memory and this conversation with their main " &
           "assistant and their other agents; earlier replies in the history may " &
           "come from them. Answer as " & a.name & ", in the user's language.\n\n"
  if notes.strip.len > 0:
    result.add("## Your notes\nThings you wrote down in earlier turns:\n" &
               notes.strip & "\n\n")
  result.add(toolsSuffix)

# ── Tools for an agent that is consulted ──────────────────────────────────────

const
  ConsultedAgentToolNames* = [SessionSearchToolName, CurrentTimeToolName,
                              CalcToolName, WebSearchToolName, FetchToolName,
                              WebFetchToolName]
    ## Read-only: an agent asked by another (ask_agent, a room) may look things
    ## up but not act, and never reaches another agent (no ask_agent or
    ## convene_agents, so no chain). The web tools still pass the user's web
    ## policy when they run.
  MaxConsultedToolRounds* = 4
    ## Tool rounds before the agent must answer: the next request offers none.
  ConsultDeadlineMs* = 120_000
    ## Wall-clock time one consulted agent has, tool rounds included.

func consultedAgentToolDescriptions*(webSearch: bool): seq[ToolDescription] =
  ## The tools offered to a consulted agent; `web_search` only when a search
  ## key exists (as for the main assistant).
  result = @[
    ToolDescription(name: SessionSearchToolName, description: SessionSearchToolDescription,
                    schemaJson: SessionSearchToolSchema),
    ToolDescription(name: CurrentTimeToolName, description: CurrentTimeToolDescription,
                    schemaJson: CurrentTimeToolSchema),
    ToolDescription(name: CalcToolName, description: CalcToolDescription,
                    schemaJson: CalcToolSchema),
    ToolDescription(name: FetchToolName, description: FetchToolDescription,
                    schemaJson: FetchToolSchema),
    ToolDescription(name: WebFetchToolName, description: WebFetchToolDescription,
                    schemaJson: WebFetchToolSchema),
  ]
  if webSearch:
    result.insert(ToolDescription(name: WebSearchToolName,
                                  description: WebSearchToolDescription,
                                  schemaJson: WebSearchToolSchema), 3)
