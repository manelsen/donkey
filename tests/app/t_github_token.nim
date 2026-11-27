## `/github` (E11.2): each person keeps their own GitHub token, given only in
## a private conversation; the instance's token keeps doing the reading.

import std/[strutils, tables, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/app/github_token

var gStore {.threadvar.}: Table[string, string]

proc fakeSecrets(): PersonSecretsPort =
  gStore = initTable[string, string]()
  PersonSecretsPort(
    get: proc(userId: UserId; name: string): Result[string, string] {.gcsafe, raises: [].} =
      ok(gStore.getOrDefault($userId & "/" & name)),
    set: proc(userId: UserId; name, value: string): Result[void, string] {.gcsafe, raises: [].} =
      gStore[$userId & "/" & name] = value
      ok(),
    remove: proc(userId: UserId; name: string): Result[void, string] {.gcsafe, raises: [].} =
      gStore.del($userId & "/" & name)
      ok())

const Pat = "github_pat_11AAAAAAA0abcdefghijklmnopqrstuvwxyz0123456789"

proc runTests*() =
  suite "/github":
    test "bare: says whether a token is kept, and how to give one":
      let s = fakeSecrets()
      check "/github token" in githubCommand(s, UserId("ana"), "", privateChat = true).get
      check s.set(UserId("ana"), GithubTokenSecret, Pat).isOk
      check "configurado" in githubCommand(s, UserId("ana"), "", privateChat = true).get

    test "a token in a private chat is kept for that person only":
      let s = fakeSecrets()
      let r = githubCommand(s, UserId("ana"), "token " & Pat, privateChat = true)
      check r.isOk and Pat notin r.get
      check s.get(UserId("ana"), GithubTokenSecret).get == Pat
      check s.get(UserId("bob"), GithubTokenSecret).get == ""

    test "a token outside a private chat is refused and the person told to revoke it":
      let s = fakeSecrets()
      let r = githubCommand(s, UserId("ana"), "token " & Pat, privateChat = false)
      check r.isErr and "revogue" in r.error and Pat notin r.error
      check s.get(UserId("ana"), GithubTokenSecret).get == ""

    test "something that is not a GitHub token is refused":
      let s = fakeSecrets()
      check githubCommand(s, UserId("ana"), "token hunter2", privateChat = true).isErr
      check githubCommand(s, UserId("ana"), "token", privateChat = true).isErr

    test "forgetting removes it":
      let s = fakeSecrets()
      discard githubCommand(s, UserId("ana"), "token " & Pat, privateChat = true)
      check githubCommand(s, UserId("ana"), "esquecer", privateChat = false).isOk
      check s.get(UserId("ana"), GithubTokenSecret).get == ""

when isMainModule:
  runTests()
