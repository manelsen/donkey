## task_tools.nim — background task spawning, job management, and skill operations.
##
## The job system (task / await / cancel_job / submit_result) implements
## parallel subtask execution within a single agent turn.

import std/tables
import chronos
import chronos/asyncsync
import results
import ../session_state
import ../skill_runtime
import ../../domain/message
import ../../ports/memory
import ../../ports/provider

# ── task (background job) ────────────────────────────────────────────────────

proc performTask*(prompt, context: string;
                  completeFn: CompleteFn): string {.gcsafe, raises: [].} =
  try:
    var h = newHistory()
    if context.len > 0: h.addUser("Context:\n" & context)
    h.addUser(prompt)
    let req  = buildPrompt("You are a focused AI assistant completing a specific subtask." &
                           " Be concise and direct.", h, "")
    let resp = completeFn(req)
    if resp.isErr: return "Task error: " & resp.error
    resp.value.text
  except Exception as e:
    "Task error: " & e.msg

proc nextJobId*(state: SessionState): string {.gcsafe, raises: [].} =
  let id = "job-" & $state.jobCounter
  inc state.jobCounter
  id

proc buildTaskStartedText*(jobId: string): string {.gcsafe, raises: [].} =
  "job_id=" & jobId & "\nstatus=running"

proc spawnTaskJob*(state: SessionState;
                   prompt, context: string;
                   completeFn: CompleteFn): string {.gcsafe, raises: [].} =
  proc runTaskJob(jobFuture: Future[string];
                  prompt, context: string;
                  completeFn: CompleteFn): Future[void] {.async, gcsafe.} =
    await sleepAsync(chronos.milliseconds(1))
    if not jobFuture.finished():
      jobFuture.complete(performTask(prompt, context, completeFn))

  let jobId = state.nextJobId()
  let jobFuture = newFuture[string]()
  state.jobs[jobId] = JobState(future: jobFuture, done: false, result: "")
  asyncSpawn runTaskJob(jobFuture, prompt, context, completeFn)
  jobId

# ── skill management ─────────────────────────────────────────────────────────

proc performManageSkills*(memory: MemoryRuntimePort;
                          uid: UserId;
                          value: string;
                          registry = ""): Result[string, string] {.gcsafe, raises: [].} =
  try:
    applySkillCommand(memory.paddockDir(uid), value, registry = registry)
  except Exception as e:
    err("Error: " & e.msg)
