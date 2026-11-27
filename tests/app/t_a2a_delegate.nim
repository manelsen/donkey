## E13.4: delegate_to_agent — only listed agents, always approved, the task
## sent as approved, the answer brought back (v1.0, or v0.3 when the agent
## answers "method not found").

import std/[json, strutils, unittest]
import chronos
import donkey/adapters/filesystem/fs_adapter
import donkey/app/native_tools
import donkey/app/session_state
import donkey/app/offloop_io
import donkey/app/approval_runtime
import donkey/app/credential_runtime
import donkey/config/environment
import donkey/core/pipeops
import donkey/core/log
import donkey/core/security/approval
import donkey/ports/approval
import donkey/core/types
import donkey/domain/message
import donkey/domain/a2a/a2a_client_pure
import donkey/ports/http

var gSent {.threadvar.}: seq[(string, string, string, seq[string])]  ## url, body, auth, allowHosts
var gAnswers {.threadvar.}: seq[string]
var gDecision {.threadvar.}: ApprovalStatus
var gSummaries {.threadvar.}: seq[string]

proc fakePost(url, body: string; headers: seq[HttpHeader]; allowHosts: seq[string]):
    Future[Result[HttpResponse, string]] {.async: (raises: []).} =
  var auth = ""
  for (k, v) in headers:
    if k == "Authorization": auth = v
  gSent.add((url, body, auth, allowHosts))
  let answer = if gAnswers.len > 0: gAnswers[0] else: "{}"
  if gAnswers.len > 1: gAnswers.delete(0)
  return ok(HttpResponse(status: 200, body: answer))

const Planner = A2aAgent(name: "planner", url: "https://p.example/a2a", tokenEnv: "A2A_PLANNER_TOKEN",
                         host: "p.example", description: "Planeja viagens")

proc task(state: string; text = ""; id = "t1"): string =
  var t = %*{"id": id, "status": {"state": state}}
  if text.len > 0: t["artifacts"] = %*[{"parts": [{"text": text}]}]
  $(%*{"jsonrpc": "2.0", "id": 1, "result": {"task": t}})

proc prepare(answers: openArray[string]; decision = apsApproved; token = "tok-planner") =
  gSent = @[]
  gSummaries = @[]
  gAnswers = @answers
  gDecision = decision
  useOffLoopIo(OffLoopIo(httpPost: fakePost))
  useCredentials(environmentOf({"A2A_PLANNER_TOKEN": token}))
  useA2aAgents(@[Planner])
  configureApprovalService(ApprovalStorePort(
    create: proc(userId: string; channel: string; toolName, summary: string;
                 ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
      gSummaries.add summary
      ok(ApprovalRequest(id: "abcdefgh", userId: userId, channel: channel, toolName: toolName,
                         summary: summary, createdAtMs: 0, expiresAtMs: 60_000, status: apsPending)),
    status: proc(id: string): Result[ApprovalStatus, string] {.gcsafe, raises: [].} = ok(gDecision),
    decide: proc(id, userId: string; approved: bool; admin: bool): Result[void, string] {.gcsafe, raises: [].} = ok(),
    listPending: proc(userId: string): Result[seq[ApprovalRequest], string] {.gcsafe, raises: [].} =
      ok(newSeq[ApprovalRequest]())), @[])

proc call(input: JsonNode): NativeToolResult =
  let ctx = NativeCtx(uid: UserId("ana"), channel: ckTelegram, fs: newFsAdapter(),
                      outbox: newAsyncQueue[OutboundMessage](8), approval: currentApprovalService(),
                      log: newLogger("t_a2a_delegate", lvlError))
  waitFor executeNativeTool(ToolCallRequest(id: "1", name: DelegateToolName, inputJson: $input),
                            ctx, newSessionState(), @[])

let ask = %*{"agent": "planner", "task": "reserve um hotel em Lisboa"}

proc runTests*() =
  suite "delegate_to_agent (E13.4)":
    test "approved: the task goes as shown, with the agent's token, to its host only":
      prepare([task("TASK_STATE_COMPLETED", "Hotel reservado.")])
      let r = call(ask)
      check "Hotel reservado." in r.text
      check gSummaries.len == 1 and gSummaries[0].endsWith("reserve um hotel em Lisboa")
      check gSent.len == 1
      check gSent[0][0] == "https://p.example/a2a" and gSent[0][2] == "Bearer tok-planner"
      check gSent[0][3] == @["p.example"]
      let sent = parseJson(gSent[0][1])
      check sent["method"].getStr == "SendMessage"
      check sent["params"]["message"]["parts"][0]["text"].getStr == "reserve um hotel em Lisboa"

    test "denied: nothing is sent":
      prepare([task("TASK_STATE_COMPLETED", "x")], decision = apsDenied)
      let r = call(ask)
      check gSent.len == 0 and "negad" in r.text.toLowerAscii

    test "an agent not in [[a2a.agents]] is refused, without asking":
      prepare([task("TASK_STATE_COMPLETED", "x")])
      let r = call(%*{"agent": "outro", "task": "oi"})
      check gSent.len == 0 and gSummaries.len == 0 and "planner" in r.text

    test "without the agent's token nothing is asked or sent, and the variable is named":
      prepare([task("TASK_STATE_COMPLETED", "x")], token = "")
      let r = call(ask)
      check gSent.len == 0 and gSummaries.len == 0 and "A2A_PLANNER_TOKEN" in r.text

    test "a v0.3 agent: method not found, then message/send":
      prepare([$(%*{"jsonrpc": "2.0", "id": 1, "error": {"code": -32601, "message": "Method not found"}}),
               $(%*{"jsonrpc": "2.0", "id": 1, "result": {"kind": "task", "id": "t9",
                    "status": {"state": "completed", "message": {"parts": [{"kind": "text", "text": "ok"}]}}}})])
      let r = call(ask)
      check r.text.contains("ok") and gSent.len == 2
      check parseJson(gSent[1][1])["method"].getStr == "message/send"
      check gSummaries.len == 1   ## one approval for the one task

    test "still working: asked again until it finishes":
      prepare([task("TASK_STATE_WORKING"), task("TASK_STATE_COMPLETED", "pronto")])
      let r = call(ask)
      check "pronto" in r.text and gSent.len == 2
      let poll = parseJson(gSent[1][1])
      check poll["method"].getStr == "GetTask" and poll["params"]["id"].getStr == "t1"

    test "a failed task is reported as such":
      prepare([task("TASK_STATE_FAILED", "sem quartos")])
      let r = call(ask)
      check "failed" in r.text and "sem quartos" in r.text

when isMainModule:
  runTests()
