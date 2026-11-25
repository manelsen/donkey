## Approvals that stand (PRD-roadmap E5.2): a request the person may approve
## once, always (for that key, e.g. one MCP server's sampling), or deny. An
## approval that stands is kept on disk, asked no more, and can be revoked.

import std/[options, os, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/app/approval_runtime
import donkey/adapters/state/approval_store
import donkey/adapters/state/standing_approvals
import donkey/core/log
import donkey/core/pipeops
import donkey/core/security/approval
import donkey/core/types
import donkey/domain/message
import donkey/ports/approval

const Tmp = "/tmp/donkey_standing_approvals_tests"
let testLog = newLogger("test.standing", lvlError)

proc setup(tag: string): (ApprovalStore, StandingApprovalPort) =
  removeDir(Tmp / tag)
  let store = newApprovalStore(Tmp / tag / "approvals.json")
  let standing = newStandingApprovals(Tmp / tag / "standing_approvals.json").toStandingPort()
  configureApprovalService(store.toApprovalPort(), @[], timeoutSec = 5.0,
                           standing = standing)
  (store, standing)

proc decideWhenAsked(outbox: AsyncQueue[OutboundMessage]; answer: string): Future[string] {.async.} =
  ## Plays the person: waits for the card, presses a button, returns the card.
  let card = await outbox.get()
  var data = ""
  for row in card.keyboard:
    for (label, cb) in row:
      if cb.endsWith(":" & answer): data = cb
  discard tryHandleApprovalInput(card.userId, data)
  return card.text

proc runTests*() =
  suite "standing approvals":

    test "the card offers once, always and deny, and 'once' asks again next time":
      let (_, _) = setup("once")
      defer: resetApprovalService()
      let outbox = newAsyncQueue[OutboundMessage]()
      let service = currentApprovalService()
      let answering = decideWhenAsked(outbox, "allow")
      let d = waitFor requestStandingApproval(service, UserId("u1"), ckTelegram, outbox,
        "sampling:abc", "Sampling", "O servidor quer usar o modelo", testLog)
      check d == adApproved
      check "O servidor quer usar o modelo" in waitFor(answering)
      let answering2 = decideWhenAsked(outbox, "deny")
      check waitFor(requestStandingApproval(service, UserId("u1"), ckTelegram, outbox,
        "sampling:abc", "Sampling", "de novo", testLog)) == adDenied
      discard waitFor answering2

    test "'always' approves now and stands for that person and key":
      let (_, standing) = setup("always")
      defer: resetApprovalService()
      let outbox = newAsyncQueue[OutboundMessage]()
      let service = currentApprovalService()
      let answering = decideWhenAsked(outbox, "always")
      check waitFor(requestStandingApproval(service, UserId("u1"), ckTelegram, outbox,
        "sampling:abc", "Sampling", "x", testLog)) == adApproved
      discard waitFor answering
      check standing.has("u1", "sampling:abc")
      ## asked no more: no card goes out
      check waitFor(requestStandingApproval(service, UserId("u1"), ckTelegram, outbox,
        "sampling:abc", "Sampling", "y", testLog)) == adApproved
      check outbox.len == 0
      ## another person, or another key, is asked
      check not standing.has("u2", "sampling:abc")
      check not standing.has("u1", "sampling:def")

    test "a standing approval survives a restart and can be revoked":
      let (_, standing) = setup("persist")
      defer: resetApprovalService()
      check standing.grant("u1", "sampling:abc").isOk
      let again = newStandingApprovals(Tmp / "persist" / "standing_approvals.json").toStandingPort()
      check again.has("u1", "sampling:abc")
      check again.list("u1") == @["sampling:abc"]
      check again.revoke("u1", "sampling:abc").isOk
      check not newStandingApprovals(Tmp / "persist" / "standing_approvals.json").toStandingPort().has("u1", "sampling:abc")

    test "the file is readable only by the daemon's user":
      let (_, standing) = setup("mode")
      defer: resetApprovalService()
      check standing.grant("u1", "k").isOk
      check (getFilePermissions(Tmp / "mode" / "standing_approvals.json") *
             {fpGroupRead, fpOthersRead}).len == 0

when isMainModule:
  runTests()
