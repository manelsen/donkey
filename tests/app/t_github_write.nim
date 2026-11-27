## Writing on GitHub (E11.1, E11.3): under the repository's policy, with the
## token of the person who asked; what asks is posted only if approved, and
## exactly as approved.

import std/[json, strutils, tables, unittest]
import chronos
import donkey/adapters/filesystem/fs_adapter
import donkey/app/native_tools
import donkey/app/session_state
import donkey/app/offloop_io
import donkey/app/approval_runtime
import donkey/app/github_token
import donkey/core/pipeops
import donkey/core/log
import donkey/core/security/approval
import donkey/ports/approval
import donkey/core/types
import donkey/domain/message
import donkey/domain/tools/github_pure
import donkey/ports/http

var gSent {.threadvar.}: seq[(string, string, string, string)]   ## (method, url, body, auth)
var gTokens {.threadvar.}: Table[string, string]
var gDecision {.threadvar.}: ApprovalStatus
var gSummaries {.threadvar.}: seq[string]

proc fakePost(url, body: string; headers: seq[HttpHeader]; allowHosts: seq[string]):
    Future[Result[HttpResponse, string]] {.async: (raises: []).} =
  var auth = ""
  for (k, v) in headers:
    if k == "Authorization": auth = v
  gSent.add(("POST", url, body, auth))
  return ok(HttpResponse(status: 201, body: """{"number":12,"html_url":"https://github.com/o/r/issues/12"}"""))

proc fakePatch(url, body: string; headers: seq[HttpHeader]; allowHosts: seq[string]):
    Future[Result[HttpResponse, string]] {.async: (raises: []).} =
  gSent.add(("PATCH", url, body, ""))
  return ok(HttpResponse(status: 200, body: """{"html_url":"https://github.com/o/r/issues/3"}"""))

proc prepare(tokens: openArray[(string, string)]; decision = apsApproved) =
  gSent = @[]
  gSummaries = @[]
  gTokens = initTable[string, string]()
  for (u, t) in tokens: gTokens[u] = t
  gDecision = decision
  useOffLoopIo(OffLoopIo(httpPost: fakePost, httpPatch: fakePatch))
  configurePersonSecrets(PersonSecretsPort(
    get: proc(userId: UserId; name: string): Result[string, string] {.gcsafe, raises: [].} =
      ok(gTokens.getOrDefault($userId)),
    set: proc(userId: UserId; name, value: string): Result[void, string] {.gcsafe, raises: [].} = ok(),
    remove: proc(userId: UserId; name: string): Result[void, string] {.gcsafe, raises: [].} = ok()))
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

proc call(policy: GithubPolicy; input: JsonNode; user = "ana"): NativeToolResult =
  let ctx = NativeCtx(uid: UserId(user), channel: ckTelegram, fs: newFsAdapter(),
                      outbox: newAsyncQueue[OutboundMessage](8), approval: currentApprovalService(),
                      githubPolicy: policy, log: newLogger("t_github_write", lvlError))
  waitFor executeNativeTool(ToolCallRequest(id: "1", name: "github", inputJson: $input),
                            ctx, newSessionState(), @[])

let comment = %* {"action": "comment", "repo": "o/r", "number": 3, "body": "Obrigado!\n— Ana"}

proc runTests*() =
  suite "github writes":
    test "ask (the default): approved, posted exactly as shown, with the person's token":
      prepare({"ana": "github_pat_ana"})
      let r = call(GithubPolicy(), comment)
      check "Comentário publicado" in r.text
      check gSummaries.len == 1 and gSummaries[0].endsWith("Obrigado!\n— Ana")
      check gSent == @[("POST", "https://api.github.com/repos/o/r/issues/3/comments",
                        $(%* {"body": "Obrigado!\n— Ana"}), "Bearer github_pat_ana")]

    test "ask, denied: nothing is posted":
      prepare({"ana": "github_pat_ana"}, decision = apsDenied)
      let r = call(GithubPolicy(), comment)
      check "denied" in r.text.toLowerAscii or "negad" in r.text.toLowerAscii
      check gSent.len == 0

    test "allow: posted without asking; deny: refused without asking":
      prepare({"ana": "github_pat_ana"})
      let allow = parseGithubPolicy(%* {"repos": {"o/r": {"comment": "allow", "close_issue": "deny"}}}).get
      check "publicado" in call(allow, comment).text
      check gSummaries.len == 0 and gSent.len == 1
      let closing = call(allow, %* {"action": "close_issue", "repo": "o/r", "number": 3})
      check "política" in closing.text and gSent.len == 1

    test "without the person's own token nothing is written, and they are told how":
      prepare({"bob": "github_pat_bob"})
      let r = call(GithubPolicy(), comment, user = "ana")
      check "/github" in r.text and gSent.len == 0 and gSummaries.len == 0

    test "close_issue goes as PATCH":
      prepare({"ana": "github_pat_ana"})
      let allow = parseGithubPolicy(%* {"default": "allow"}).get
      check "fechada" in call(allow, %* {"action": "close_issue", "repo": "o/r", "number": 3}).text
      check gSent[0][0] == "PATCH" and gSent[0][2] == $(%* {"state": "closed"})

    test "a text too long to show whole for approval is refused, not cut":
      prepare({"ana": "github_pat_ana"})
      let long = %* {"action": "comment", "repo": "o/r", "number": 3, "body": "x".repeat(5000)}
      let r = call(GithubPolicy(), long)
      check "long" in r.text.toLowerAscii and gSent.len == 0

when isMainModule:
  runTests()
