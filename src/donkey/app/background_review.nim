## background_review — after enough turns, a copy of the agent reviews the
## conversation and keeps what deserves a skill (E7.4).
##
## The review reads the end of the conversation (domain/skills/review_pure),
## on the auxiliary route when the operator set one (DONKEY_REVIEW_PROVIDER
## and _MODEL), and may only use skill_view and skill_manage, run here on the
## person's store with every write through the guard and recorded as the
## review's. At most MaxReviewRounds rounds of tools, within a deadline. It
## runs after the turn, spawned by the orchestrator: the session and its
## history are never touched.

import std/[json, strutils, tables]
import chronos
import ../core/pipeops
import ../domain/message
import ../domain/skills/review_pure
import ../infra/thread_owner
import ../ports/fs
import ./provider_executor
import ./skill_tools

const
  MaxReviewRounds* = 4
  ReviewDeadlineMs* = 180_000

# ── Cadence, per person, on the loop ─────────────────────────────────────────

var
  gCounts {.threadvar.}: Table[string, ReviewCounts]
  gCountsOwner: ThreadOwner

proc resetReviewCounts*() =
  if gCountsOwner.isOwner("review counts"): gCounts.clear()

proc reviewDueAfterTurn*(userId: string; toolCalls: int; s: ReviewSettings): bool =
  ## Counts one finished turn of `userId`; true when their review is due.
  if not gCountsOwner.isOwner("review counts"): return false
  var c = gCounts.getOrDefault(userId)
  result = c.noteTurn(toolCalls, s)
  gCounts[userId] = c

# ── The review ───────────────────────────────────────────────────────────────

proc runTool(fs: FsRuntimePort; paddockDir: string; call: ToolCallRequest;
             nowMs: int64; by: string): (string, ToolResultKind) =
  let j =
    try: parseJson(if call.inputJson.len > 0: call.inputJson else: "{}")
    except CatchableError: newJObject()
  case call.name
  of SkillManageToolName:
    let c = parseSkillManage(j)
    if c.isErr: return (c.error, trkUsageError)
    let done = performSkillManage(fs, paddockDir, c.get, nowMs, by = by)
    if done.isErr: ("Error: " & done.error, trkOperationalError) else: (done.get, trkOutput)
  of SkillViewToolName:
    let shown = performSkillView(fs, paddockDir, j{"name"}.getStr, nowMs)
    if shown.isErr: ("Error: " & shown.error, trkOperationalError) else: (shown.get, trkOutput)
  else:
    ("Error: the review may only use skill_manage and skill_view.", trkUsageError)

proc skillAgentLoop(callModel: AsyncCompleteFn; fs: FsRuntimePort; paddockDir: string;
                    system, content, provider, model, by: string;
                    nowMs: int64): Future[Result[string, string]] {.async.} =
  let tools = @[
    ToolDescription(name: SkillManageToolName, description: SkillManageToolDescription,
                    schemaJson: SkillManageToolSchema),
    ToolDescription(name: SkillViewToolName, description: SkillViewToolDescription,
                    schemaJson: SkillViewToolSchema)]
  var convo = newHistory()
  convo.addUser(content)
  var round = 0
  var actions: seq[string]
  while true:
    let offered = if round < MaxReviewRounds: tools else: @[]
    let resp =
      try:
        await callModel(CompletionRequest(system: system, messages: convo, tools: offered,
                                          providerOverride: provider, modelOverride: model))
      except CancelledError as e: raise e
      except Exception as e:  ## effect boundary: callee raises are unannotated
        return err(Result[string, string], "review: " & e.msg)
    if resp.isErr:
      return err(Result[string, string], "review: " & resp.error)
    let answer = resp.get
    if answer.toolCalls.len == 0 or offered.len == 0:
      return ok(Result[string, string],
                if actions.len > 0: actions.join("; ") else: answer.text.strip)
    inc round
    convo.addAssistantWithToolCalls(answer.text, answer.toolCalls, reasoning = answer.reasoning)
    for call in answer.toolCalls:
      let (text, kind) = runTool(fs, paddockDir, call, nowMs, by)
      if call.name == SkillManageToolName and kind == trkOutput and not text.startsWith("No learned"):
        actions.add text
      convo.addToolResult(call.id, call.name, text, kind)

proc runSkillAgent*(callModel: AsyncCompleteFn; fs: FsRuntimePort; paddockDir: string;
                    system, content, provider, model, by: string;
                    nowMs: int64): Future[Result[string, string]] {.async.} =
  ## A copy of the agent that may only view and write the person's skills
  ## (as `by`): the review's and the curator's. What it changed, or its
  ## last words, within ReviewDeadlineMs.
  if callModel == nil:
    return err(Result[string, string], by & ": no model available")
  let running = skillAgentLoop(callModel, fs, paddockDir, system, content, provider, model, by, nowMs)
  if not await withTimeout(running, chronos.milliseconds(ReviewDeadlineMs)):
    return err(Result[string, string], by & ": took too long")
  return running.read()

proc runReview*(callModel: AsyncCompleteFn; fs: FsRuntimePort; paddockDir: string;
                history: seq[ChatMessage]; s: ReviewSettings;
                nowMs: int64): Future[Result[string, string]] {.async.} =
  ## What the review kept (or its last words), within ReviewDeadlineMs.
  var docs: seq[SkillDoc]
  for k in newLearnedSkills(fs, paddockDir).list(): docs.add k.doc
  let system = ReviewInstructions & "\n\n" &
    (if docs.len > 0: skillsIndex(docs) else: "## Skills you learned\n(none yet)\n")
  return await runSkillAgent(callModel, fs, paddockDir, system,
    "The conversation to review:\n\n" & reviewTranscript(history),
    s.provider, s.model, "review", nowMs)
