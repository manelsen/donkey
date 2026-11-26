## github and git_inspect, the application half (second round, front 2):
## each call runs off the event loop through the installed OffLoopIo; without
## it, or without GITHUB_TOKEN, the tool refuses instead of blocking. A real
## git run checks that a hostile repository config cannot run a program.

import std/[json, os, osproc, strutils, unittest]
import chronos
import donkey/app/offloop_io
import donkey/app/tools/github_git_tools
import donkey/adapters/tools/offloop_jobs
import donkey/core/pipeops
import donkey/ports/http
import donkey/ports/process

type Seen = ref object
  urls: seq[string]
  hosts: seq[seq[string]]
  argvs: seq[seq[string]]

proc fakeIo(s: Seen; status = 200; body = "[]"; output = "## main"): OffLoopIo =
  OffLoopIo(
    httpGet: proc(url: string; headers: seq[HttpHeader]; allowHosts: seq[string]):
        Future[Result[HttpResponse, string]] {.async: (raises: []), gcsafe.} =
      {.cast(gcsafe).}:
        s.urls.add url
        s.hosts.add allowHosts
      return ok(HttpResponse(status: status, body: body)),
    processRun: proc(spec: ProcessSpec): Future[Result[ProcessOutput, string]] {.async: (raises: []), gcsafe.} =
      {.cast(gcsafe).}:
        s.argvs.add spec.argv
      return ok(ProcessOutput(output: output, exitCode: 0)))

proc realIo(): OffLoopIo =
  ## The real jobs, answered in place (the daemon runs them on the executor).
  OffLoopIo(processRun: proc(spec: ProcessSpec): Future[Result[ProcessOutput, string]] {.async: (raises: []), gcsafe.} =
    return processJob(ProcessJob(spec: spec)))

proc runTests*() =
  suite "github tool":

    test "a read goes to api.github.com only, with the token":
      let s = Seen()
      let r = waitFor performGithub(%* {"action": "list_issues", "repo": "a/b"}, "ghp_x", fakeIo(s))
      check r.isOk and r.get.startsWith("[GitHub content")
      check s.urls == @["https://api.github.com/repos/a/b/issues?state=open&per_page=20"]
      check s.hosts == @[@["api.github.com"]]

    test "without a token, without the off-loop runner, or with a bad call: an error, no request":
      let s = Seen()
      check (waitFor performGithub(%* {"action": "list_issues", "repo": "a/b"}, "", fakeIo(s))).isErr
      check (waitFor performGithub(%* {"action": "list_issues", "repo": "a/b"}, "t", OffLoopIo())).isErr
      check (waitFor performGithub(%* {"action": "create_issue", "repo": "a/b"}, "t", fakeIo(s))).isErr
      check s.urls.len == 0

    test "GitHub's error status reaches the agent":
      let r = waitFor performGithub(%* {"action": "get_issue", "repo": "a/b", "number": 1}, "t",
                                    fakeIo(Seen(), status = 404, body = """{"message":"Not Found"}"""))
      check r.isErr and "Not Found" in r.error

  suite "git_inspect tool":

    test "the command runs through the runner, with the guards, in the repository":
      let s = Seen()
      let c = parseGitInspectContext(%* {"action": "status", "path": "repo"}).get
      let r = waitFor performGitInspect(c, "/p/repo", fakeIo(s))
      check r.isOk and "## main" in r.get
      check s.argvs.len == 1 and "core.fsmonitor=false" in s.argvs[0] and "/p/repo" in s.argvs[0]

    test "without the runner: an error":
      let c = parseGitInspectContext(%* {"action": "status", "path": "repo"}).get
      check (waitFor performGitInspect(c, "/p/repo", OffLoopIo())).isErr

    test "a hostile repository config cannot run a program on status":
      if findExe("git").len == 0:
        skip()
      else:
        let dir = getTempDir() / "donkey_git_hostile"
        let marker = getTempDir() / "donkey_git_hostile_ran"
        removeDir(dir); removeFile(marker); createDir(dir)
        discard execCmd("git -C " & quoteShell(dir) & " init -q")
        writeFile(dir / "a.txt", "x")
        let hook = dir / "hook.sh"
        writeFile(hook, "#!/bin/sh\ntouch " & quoteShell(marker) & "\n")
        setFilePermissions(hook, {fpUserRead, fpUserWrite, fpUserExec})
        discard execCmd("git -C " & quoteShell(dir) & " config core.fsmonitor " & quoteShell(hook))
        let c = parseGitInspectContext(%* {"action": "status", "path": "repo"}).get
        let r = waitFor performGitInspect(c, dir, realIo())
        check r.isOk and "a.txt" in r.get
        check not fileExists(marker)

when isMainModule:
  runTests()
