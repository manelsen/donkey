## The github tool, the pure half (second round, front 2): read-only access
## to issues, pull requests, commits and code search through the REST API.
## What comes back is written by third parties, so the tool says so.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/tools/github_pure

proc ctxOf(s: string): Result[GithubContext, string] = parseGithubContext(parseJson(s))

proc runTests*() =
  suite "github — reading the call":

    test "actions and their required fields":
      check ctxOf("""{"action":"list_issues","repo":"nim-lang/Nim"}""").get.state == "open"
      check ctxOf("""{"action":"get_issue","repo":"nim-lang/Nim","number":42}""").get.number == 42
      check ctxOf("""{"action":"get_issue","repo":"nim-lang/Nim"}""").isErr
      check ctxOf("""{"action":"search_code","query":"proc foo"}""").get.query == "proc foo"
      check ctxOf("""{"action":"search_code"}""").isErr
      check ctxOf("""{"action":"create_issue","repo":"a/b"}""").isErr   ## read only
      check ctxOf("""{"action":"list_prs"}""").isErr

    test "a repository is owner/name, nothing that could leave the path":
      check ctxOf("""{"action":"list_prs","repo":"a/b"}""").isOk
      check ctxOf("""{"action":"list_prs","repo":"a/../../x"}""").isErr
      check ctxOf("""{"action":"list_prs","repo":"a/b?x=1"}""").isErr
      check ctxOf("""{"action":"list_prs","repo":"https://github.com/a/b"}""").isErr

    test "the limit stays between 1 and 50; the state is open, closed or all":
      check ctxOf("""{"action":"list_issues","repo":"a/b","limit":500}""").get.limit == 50
      check ctxOf("""{"action":"list_issues","repo":"a/b","limit":0}""").get.limit == 1
      check ctxOf("""{"action":"list_issues","repo":"a/b","state":"merged"}""").isErr

  suite "github — the request":

    test "each action's URL":
      check githubUrl(ctxOf("""{"action":"list_issues","repo":"a/b","limit":5}""").get) ==
        "https://api.github.com/repos/a/b/issues?state=open&per_page=5"
      check githubUrl(ctxOf("""{"action":"get_pr","repo":"a/b","number":7}""").get) ==
        "https://api.github.com/repos/a/b/pulls/7"
      check githubUrl(ctxOf("""{"action":"list_commits","repo":"a/b","branch":"dev","limit":3}""").get) ==
        "https://api.github.com/repos/a/b/commits?sha=dev&per_page=3"
      check githubUrl(ctxOf("""{"action":"search_code","query":"proc foo","repo":"a/b"}""").get) ==
        "https://api.github.com/search/code?q=proc+foo+repo%3Aa%2Fb&per_page=20"

    test "the headers: the token, the API version, a user agent":
      let h = githubHeaders("ghp_x")
      check ("Authorization", "Bearer ghp_x") in h
      check ("Accept", "application/vnd.github+json") in h
      check ("X-GitHub-Api-Version", "2022-11-28") in h

  suite "github — what the agent reads":

    test "an issue list skips pull requests and keeps one line each":
      let body = """[{"number":12,"title":"Crash on start","state":"open","user":{"login":"belle"},"updated_at":"2026-11-25T10:00:00Z","comments":3},
                     {"number":13,"title":"A PR","state":"open","user":{"login":"x"},"pull_request":{}}]"""
      let text = formatGithub(ctxOf("""{"action":"list_issues","repo":"a/b"}""").get, 200, body).get
      check "#12 [open] Crash on start — belle" in text
      check "#13" notin text
      check text.startsWith(ThirdPartyNote)

    test "an issue shows its body, cut":
      let body = $(%* {"number": 12, "title": "Crash", "state": "open", "user": {"login": "belle"},
                       "body": "x".repeat(10_000), "labels": [{"name": "bug"}], "html_url": "https://github.com/a/b/issues/12"})
      let text = formatGithub(ctxOf("""{"action":"get_issue","repo":"a/b","number":12}""").get, 200, body).get
      check "labels: bug" in text and "https://github.com/a/b/issues/12" in text
      check text.len < 7_000

    test "a pull request shows its branches and merge state":
      let body = $(%* {"number": 7, "title": "Fix", "state": "open", "user": {"login": "b"},
                       "head": {"ref": "fix"}, "base": {"ref": "main"}, "merged": false,
                       "mergeable": true, "body": "desc", "html_url": "u"})
      let text = formatGithub(ctxOf("""{"action":"get_pr","repo":"a/b","number":7}""").get, 200, body).get
      check "fix → main" in text and "mergeable: true" in text

    test "commits and code search, one line each":
      let commits = """[{"sha":"abcdef1234567","commit":{"message":"feat: x\n\nbody","author":{"name":"B","date":"2026-11-25T10:00:00Z"}}}]"""
      check "abcdef1 feat: x — B" in formatGithub(ctxOf("""{"action":"list_commits","repo":"a/b"}""").get, 200, commits).get
      let found = """{"total_count":1,"items":[{"path":"src/x.nim","repository":{"full_name":"a/b"},"html_url":"u"}]}"""
      check "a/b: src/x.nim" in formatGithub(ctxOf("""{"action":"search_code","query":"q"}""").get, 200, found).get

    test "a list action that gets an object back is an error, not an empty list":
      let r = formatGithub(ctxOf("""{"action":"list_issues","repo":"a/b"}""").get, 200,
                           """{"message":"API rate limit exceeded"}""")
      check r.isErr and "rate limit" in r.error

    test "a branch is letters, digits and ._/- only":
      check ctxOf("""{"action":"list_commits","repo":"a/b","branch":"feat/x-1.2"}""").isOk
      check ctxOf("""{"action":"list_commits","repo":"a/b","branch":"a%26per_page=1"}""").isErr
      check ctxOf("""{"action":"list_commits","repo":"a/b","branch":"a+b"}""").isErr

    test "an error status says what GitHub said":
      let r = formatGithub(ctxOf("""{"action":"get_issue","repo":"a/b","number":1}""").get, 404,
                           """{"message":"Not Found"}""")
      check r.isErr and "404" in r.error and "Not Found" in r.error

proc runWriteTests*() =
  suite "github — writing (E11.1)":
    test "the four writes and what each needs":
      check parseGithubContext(%* {"action": "create_issue", "repo": "o/r", "title": "Bug", "body": "x"}).isOk
      check parseGithubContext(%* {"action": "create_issue", "repo": "o/r", "body": "x"}).isErr      ## title
      check parseGithubContext(%* {"action": "comment", "repo": "o/r", "number": 3, "body": "oi"}).isOk
      check parseGithubContext(%* {"action": "comment", "repo": "o/r", "number": 3}).isErr          ## body
      check parseGithubContext(%* {"action": "add_labels", "repo": "o/r", "number": 3, "labels": ["bug"]}).isOk
      check parseGithubContext(%* {"action": "add_labels", "repo": "o/r", "number": 3, "labels": []}).isErr
      check parseGithubContext(%* {"action": "close_issue", "repo": "o/r", "number": 3}).isOk
      check parseGithubContext(%* {"action": "merge_pr", "repo": "o/r", "number": 3}).isErr        ## never
      check isWriteAction("comment") and not isWriteAction("get_issue")

    test "each write is one request: method, URL and the exact JSON":
      let issue = githubWriteRequest(parseGithubContext(%* {"action": "create_issue", "repo": "o/r",
        "title": "Bug", "body": "linha 1\nlinha 2"}).get)
      check issue == (meth: "POST", url: "https://api.github.com/repos/o/r/issues",
                      body: $(%* {"title": "Bug", "body": "linha 1\nlinha 2"}))
      check githubWriteRequest(parseGithubContext(%* {"action": "comment", "repo": "o/r", "number": 3,
        "body": "oi"}).get) == (meth: "POST", url: "https://api.github.com/repos/o/r/issues/3/comments",
        body: $(%* {"body": "oi"}))
      check githubWriteRequest(parseGithubContext(%* {"action": "add_labels", "repo": "o/r", "number": 3,
        "labels": ["bug", "p1"]}).get).body == $(%* {"labels": ["bug", "p1"]})
      check githubWriteRequest(parseGithubContext(%* {"action": "close_issue", "repo": "o/r",
        "number": 3}).get) == (meth: "PATCH", url: "https://api.github.com/repos/o/r/issues/3",
        body: $(%* {"state": "closed"}))

    test "the approval shows where and the exact text":
      let c = parseGithubContext(%* {"action": "comment", "repo": "o/r", "number": 3,
                                     "body": "Obrigado!\n\n— Donkey"}).get
      let summary = writeSummary(c)
      check "o/r#3" in summary and "comentar" in summary
      check summary.endsWith("Obrigado!\n\n— Donkey")

    test "the answer: what was done and where":
      let c = parseGithubContext(%* {"action": "create_issue", "repo": "o/r", "title": "Bug", "body": ""}).get
      check formatGithubWrite(c, 201, """{"number":12,"html_url":"https://github.com/o/r/issues/12"}""").get ==
        "Issue #12 aberta: https://github.com/o/r/issues/12"
      check formatGithubWrite(c, 403, """{"message":"Resource not accessible"}""").error.contains("403")

  suite "github — policy per repository (E11.3)":
    test "the default is ask; a repository's rule wins; deny stays deny":
      var p = GithubPolicy()
      check p.decide("o/r", "comment") == gpAsk
      p = parseGithubPolicy(%* {"default": "deny",
        "repos": {"o/r": {"comment": "allow", "close_issue": "deny"}, "o/x": {"*": "ask"}}}).get
      check p.decide("o/r", "comment") == gpAllow
      check p.decide("O/R", "comment") == gpAllow          ## GitHub names ignore case
      check p.decide("o/r", "close_issue") == gpDeny
      check p.decide("o/r", "create_issue") == gpDeny      ## the default
      check p.decide("o/x", "add_labels") == gpAsk
      check parseGithubPolicy(%* {"default": "maybe"}).isErr
      check parseGithubPolicy(%* {"repos": {"o/r": {"merge": "allow"}}}).isErr

when isMainModule:
  runTests()
  runWriteTests()
