## prompt_building.nim — system prompt assembly, context composition.
## Extracted from orchestrator.nim (issue #5).

import std/json
import std/strutils except strip
import std/strformat
import ../core/pipeops
import ../domain/message
import ../domain/personality
import ../domain/more_tools
import ../ports/provider

proc safeComplete*(fn: CompleteFn; req: CompletionRequest
                 ): Result[CompletionResponse, string] {.gcsafe, raises: [].} =
  try: fn(req)
  except Exception as e: err(e.msg)

type NormalTurnPrep* = object
  history*:        ConversationHistory
  context*:        string
  systemBase*:     string
  agentName*:      string
  agentTraits*:    PersonalityTraits
  identityLoaded*: bool
  obPhase*:        OnboardingPhase
  showReasoning*:  bool

type UserPayload* = object
  text*:          string
  mediaUrl*:      string
  recentContext*: string

func providerLabelFromPrefs*(prefs: string): string =
  ## Extracts "provider/model" label from PREFERENCES.md TOML content.
  ## Returns "zai-coding" (default) when not set.
  var prov = "zai-coding"
  var mdl  = ""
  for line in strutils.splitLines(prefs):
    let parts = strutils.split(line, '=', 1)
    if parts.len != 2: continue
    let k = strutils.strip(parts[0])
    let v = strutils.strip(parts[1]).strip(chars = {'"'})
    case k
    of "provider": prov = v
    of "model":    mdl  = v
    else: discard
  if mdl.len > 0: prov & "/" & mdl else: prov

func orchToolsSuffix*(tools: seq[ToolDescription]): string =
  if tools.len == 0: return ""
  result = "\n\n## Available tools\n\n"
  result.add "You have access to the following tools. When a task requires one of them, " &
             "call it — do not tell the user you cannot access files, the web, or run commands.\n\n"
  if tools.anyIt(it.name == ManageSkillsToolName):
    result.add "You can install and enable skills for the current user with `manage_skills`. " &
               "Never say your toolset is fixed or that you cannot install skills. " &
               "If the user asks whether you can install skills, how skill installation works, " &
               "or you discover a missing capability that could be provided by a skill, " &
               "use `manage_skills` or explain that you can search/install/enable a skill for them. " &
               "If the user has not provided a specific skill slug or capability yet, ask what they want to add " &
               "or offer to search the registry. " &
               "After installing or enabling a skill, tell the user it becomes available on their next message.\n\n"
  if tools.anyIt(it.name == ReadFileToolName) and tools.anyIt(it.name == EditFileToolName):
    result.add "For `edit_file`, first call `read_file` on the same file and reuse the exact `LINE#ID` anchors it returned. " &
               "Never invent anchors, reuse stale anchors from an older read, or substitute plain line numbers/text snippets. " &
               "`read_file` and `edit_file` operate on the same workspace as `bash`; do not claim they use a different filesystem just because errors show host paddock paths.\n\n"
  if tools.anyIt(it.name == FsListToolName) or tools.anyIt(it.name == FsReadToolName) or
      tools.anyIt(it.name == FsWriteToolName) or tools.anyIt(it.name == TextSearchToolName) or
      tools.anyIt(it.name == TextReadToolName) or tools.anyIt(it.name == TextReplaceToolName) or
      tools.anyIt(it.name == JsonQueryToolName) or tools.anyIt(it.name == TableQueryToolName) or
      tools.anyIt(it.name == HttpFetchToolName) or tools.anyIt(it.name == ArchiveExtractToolName) or
      tools.anyIt(it.name == ArchiveCreateToolName):
    result.add "Prefer the structured native tools (`fs_*`, `text_*`, `json_query`, `table_query`, `http_fetch`, `archive_*`) for file, search, data, and HTTP work. " &
               "Use them instead of `find`, `grep`, `sed`, `sort`, or `bash` when they cover the task, because they return composable JSON. " &
               "For common filesystem + search + JSON flows, prefer passing structured JSON results between tools instead of parsing text with shell commands. " &
               "Use `bash` only when the task truly needs open-ended shell behavior, external programs, or a workflow that the structured tools do not cover.\n\n"
  if tools.len > 0:
    result.add "When the user asks you to test, audit, or list tool status, ground the answer in the actual tool results from this turn. " &
               "Report status per tool, and if a tool failed, cite the exact tool name and error text. " &
               "Do not collapse mixed results into a generic request-error message when some tool calls succeeded.\n\n"
  if tools.anyIt(it.name == ReadFileToolName) or tools.anyIt(it.name == FindToolName) or tools.anyIt(it.name == GrepToolName):
    result.add "Local file tools are restricted to the current workspace. Use relative paths, `.` or `/workspace` for workspace root. Do not use `/` unless you literally mean the container root, which will usually be rejected.\n\n"
  for td in tools:
    result.add &"- **{td.name}**: {td.description}\n"

func buildSystemBase*(agentTraits: PersonalityTraits;
                      agentName: string;
                      toolsSuffix: string): string =
  let personalityPrompt = buildPersonalityPrompt(agentTraits, agentName)
  (if personalityPrompt.len > 0:
     personalityPrompt & "\n\n"
   else:
     "You are a personal AI assistant.\n\n") &
  "Be helpful and remember what the user tells you. " &
  "Respond in the user's preferred language." &
  toolsSuffix

proc decodeUserPayload*(payload: string): UserPayload =
  ## Decodes the session payload envelope produced by ensureSession.
  ## Plain text payloads pass through unchanged.
  result = UserPayload(text: payload)
  if payload.len == 0 or payload[0] != '{':
    return
  try:
    let j = parseJson(payload)
    result.text = j.getOrDefault("text").getStr(payload)
    result.mediaUrl = j.getOrDefault("mediaUrl").getStr("")
    result.recentContext = j.getOrDefault("recentContext").getStr("")
  except CatchableError:
    discard

proc mergeUserPayloads*(payloads: openArray[string]): string =
  if payloads.len == 0:
    return ""
  if payloads.len == 1:
    return payloads[0]
  var mergedText: seq[string] = @[]
  var mediaUrl = ""
  var recentContext = ""
  for raw in payloads:
    let decoded = decodeUserPayload(raw)
    if decoded.text.strip.len > 0:
      mergedText.add(decoded.text)
    if decoded.mediaUrl.len > 0:
      mediaUrl = decoded.mediaUrl
    if recentContext.len == 0 and decoded.recentContext.len > 0:
      recentContext = decoded.recentContext
  let text = mergedText.join("\n\n")
  if mediaUrl.len == 0 and recentContext.len == 0:
    return text
  $(%* {
    "text": text,
    "mediaUrl": mediaUrl,
    "recentContext": recentContext,
  })

func addUserTurn*(history: ConversationHistory;
                  userText: string;
                  userImageUrl: string): ConversationHistory =
  result = history
  if userImageUrl.len > 0:
    result.addUserWithImage(userText, userImageUrl)
  else:
    result.addUser(userText)
  result.trimTo(20)

func buildToolLoopDoneText*(toolCallCount: int): string =
  "✅ " & $toolCallCount & " tool call(s)"

func genericProviderErrorText*(errMsg: string): string =
  let lower = errMsg.toLowerAscii()
  if lower.contains("401") or lower.contains("403") or lower.contains("unauthorized") or lower.contains("api key"):
    return "Desculpe, houve um problema de autenticação com o provedor configurado."
  if lower.contains("400") or lower.contains("bad request") or lower.contains("invalid"):
    return "Desculpe, o provedor rejeitou esta solicitação."
  if lower.contains("429") or lower.contains("rate limit") or lower.contains("500") or
     lower.contains("502") or lower.contains("503") or lower.contains("504") or
     lower.contains("timeout") or lower.contains("server_error") or lower.contains("network"):
    return "Desculpe, o provedor falhou temporariamente. Tente novamente em instantes."
  "Desculpe, ocorreu um erro ao falar com o provedor configurado."

proc explainProviderError*(errorExplainFn: CompleteFn;
                          providerErr: string): string {.gcsafe, raises: [].} =
  if errorExplainFn.isNil:
    return genericProviderErrorText(providerErr)
  var h = newHistory()
  h.addUser(
    "Explique este erro de provedor para um usuário final em português do Brasil, " &
    "em no máximo duas frases, sem jargão desnecessário, sem request id, sem JSON cru, " &
    "e com uma orientação prática curta.\n\nErro bruto:\n" & providerErr
  )
  let req = buildPrompt(
    "Você é um explicador de erros de infraestrutura para usuários finais. " &
    "Resuma o problema com linguagem humana, curta e útil.",
    h, "")
  let resp = safeComplete(errorExplainFn, req)
  if resp.isOk and resp.value.text.strip.len > 0:
    return resp.value.text.strip
  genericProviderErrorText(providerErr)

func filterThinking*(text: string): string =
  ## Removes completed <thinking>...</thinking> blocks.
  ## If a <thinking> block has no closing tag yet, strips from <thinking> to end.
  const open  = "<thinking>"
  const close = "</thinking>"
  result = ""
  var i = 0
  while i < text.len:
    let s = text.find(open, i)
    if s < 0:
      result.add(text[i .. ^1])
      break
    result.add(text[i ..< s])
    let e = text.find(close, s)
    if e < 0: break
    i = e + close.len
