## The git_inspect tool, the pure half (second round, front 2): read-only
## git commands on a repository in the paddock, with the repository's own
## configuration kept from running anything.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/tools/git_inspect_pure

proc ctxOf(s: string): Result[GitInspectContext, string] = parseGitInspectContext(parseJson(s))

proc runTests*() =
  suite "git_inspect":

    test "actions: status, log, diff, branches, show":
      check ctxOf("""{"action":"status","path":"repo"}""").isOk
      check ctxOf("""{"action":"log","path":"repo"}""").get.count == 10
      check ctxOf("""{"action":"log","path":"repo","count":500}""").get.count == 50
      check ctxOf("""{"action":"show","path":"repo","rev":"HEAD~2"}""").isOk
      check ctxOf("""{"action":"push","path":"repo"}""").isErr
      check ctxOf("""{"action":"status"}""").isErr

    test "a revision or a file cannot become an option or leave the repository":
      check ctxOf("""{"action":"show","path":"r","rev":"--output=/tmp/x"}""").isErr
      check ctxOf("""{"action":"show","path":"r","rev":"a b"}""").isErr
      check ctxOf("""{"action":"diff","path":"r","file":"-p"}""").isErr
      check ctxOf("""{"action":"diff","path":"r","file":"../../etc/passwd"}""").isErr
      check ctxOf("""{"action":"diff","path":"r","file":"src/x.nim"}""").isOk

    test "every command keeps the repository's config from running anything":
      let argv = gitArgv(ctxOf("""{"action":"status","path":"r"}""").get, "/p/r")
      check argv[0] == "git" and "-C" in argv and "/p/r" in argv
      for guard in ["core.fsmonitor=false", "core.hooksPath=/dev/null", "diff.external=",
                    "core.pager=cat", "protocol.allow=never"]:
        check guard in argv
      check argv[^3 .. ^1] == @["status", "--short", "--branch"]

    test "each action's arguments":
      check gitArgv(ctxOf("""{"action":"log","path":"r","count":3}""").get, "/r")[^3 .. ^1] ==
        @["log", "--oneline", "-n3"]
      let diff = gitArgv(ctxOf("""{"action":"diff","path":"r","file":"src/x.nim"}""").get, "/r")
      check diff[^5 .. ^1] == @["diff", "--no-ext-diff", "--no-textconv", "--", "src/x.nim"]
      check gitArgv(ctxOf("""{"action":"diff","path":"r"}""").get, "/r")[^4 .. ^1] ==
        @["diff", "--no-ext-diff", "--no-textconv", "--stat"]
      check gitArgv(ctxOf("""{"action":"show","path":"r","rev":"abc123"}""").get, "/r")[^5 .. ^1] ==
        @["show", "--no-ext-diff", "--no-textconv", "--stat", "abc123"]

    test "long output is cut and says so":
      let cut = capGitOutput("x".repeat(GitOutputChars + 100))
      check cut.len < GitOutputChars + 200 and "cut" in cut

when isMainModule:
  runTests()
