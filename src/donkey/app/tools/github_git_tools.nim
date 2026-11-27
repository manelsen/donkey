## github_git_tools — the github and git_inspect tools, the application half
## (second round, front 2). Each call is awaited through OffLoopIo, so it
## never holds the event loop; the pure halves build the request and read
## the answer.

import std/json
import chronos
import ../../core/pipeops
import ../../domain/tools/github_pure
import ../../domain/tools/git_inspect_pure
import ../../ports/process
import ../offloop_io

export github_pure, git_inspect_pure

const GitTimeoutMs = 20_000

proc performGithub*(j: JsonNode; token: string; io: OffLoopIo):
    Future[Result[string, string]] {.async: (raises: []).} =
  let c = parseGithubContext(j).valueOr:
    return err(error)
  if token.len == 0:
    return err("Error: GITHUB_TOKEN is not set")
  if io.httpGet == nil:
    return err("Error: the github tool is not available in this process")
  let resp = (await io.httpGet(githubUrl(c), githubHeaders(token), @["api.github.com"])).valueOr:
    return err("Error: GitHub request failed: " & error)
  return formatGithub(c, resp.status, resp.body)

proc performGithubWrite*(c: GithubContext; token: string; io: OffLoopIo):
    Future[Result[string, string]] {.async: (raises: []).} =
  ## One write (E11.1), with the token of the person who asked.
  let req = githubWriteRequest(c)
  let send = if req.meth == "PATCH": io.httpPatch else: io.httpPost
  if send == nil:
    return err("Error: writing to GitHub is not available in this process")
  var headers = githubHeaders(token)
  headers.add(("Content-Type", "application/json"))
  let resp = (await send(req.url, req.body, headers, @["api.github.com"])).valueOr:
    return err("Error: GitHub request failed: " & error)
  return formatGithubWrite(c, resp.status, resp.body)

proc performGitInspect*(c: GitInspectContext; repoDir: string; io: OffLoopIo):
    Future[Result[string, string]] {.async: (raises: []).} =
  if io.processRun == nil:
    return err("Error: git_inspect is not available in this process")
  let ran = (await io.processRun(argvSpec(gitArgv(c, repoDir), timeoutMs = GitTimeoutMs))).valueOr:
    return err("Error: git could not run: " & error)
  let text = capGitOutput(ran.output)
  if ran.exitCode != 0:
    return err("Error: git exited with " & $ran.exitCode & ": " & text)
  return ok(if text.len == 0: "(no output)" else: text)
