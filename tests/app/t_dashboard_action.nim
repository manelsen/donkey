## US-004 — the single dashboard action and the dashboard shell.
##
## `POST /api/sessions/{userId}/task` must act on the raw key, exactly once,
## with `tkNew`; every refusal is a status, every echoed error is redacted.

import std/[strutils, unittest]
import results
import donkey/domain/agent_message
import donkey/domain/gateway/dashboard_pure
import donkey/app/http_gateway

const Token = "secret"

var actionCalls {.threadvar.}: int
var lastRaw {.threadvar.}: string
var lastKind {.threadvar.}: TaskKind
var lastPayload {.threadvar.}: string
var actionOutcome {.threadvar.}: GatewaySessionActionOutcome

proc fakeAction(rawUserId: string; taskKind: TaskKind;
                payload: string): GatewaySessionActionOutcome {.gcsafe.} =
  inc actionCalls
  lastRaw = rawUserId
  lastKind = taskKind
  lastPayload = payload
  actionOutcome

proc resetAction() =
  actionCalls = 0
  lastRaw = ""
  lastKind = tkUserMsg
  lastPayload = "unset"
  actionOutcome = gsaoAccepted

func authorized(): string = "Bearer " & Token

proc runTests*() =
  suite "POST /api/sessions/{userId}/task":

    test "202 and the hook runs once with tkNew":
      resetAction()
      let uid = "6f1d3c2a-0b7e-4c55-9a11-3d2f9e8a7b60"
      let res = handleSessionActionRequest(
        fakeAction, uid, """{"action":"new"}""", authorized(), Token)
      check res.status == 202
      check actionCalls == 1
      check lastRaw == uid
      check lastKind == tkNew
      check lastPayload == ""

    test "404 for a raw key that does not exist, never prefixed with api:":
      resetAction()
      actionOutcome = gsaoNotFound
      let uid = "3c2a0b7e-4c55-9a11-3d2f-9e8a7b606f1d"
      let path = "/api/sessions/" & uid & "/task"
      let parsed = parseSessionTaskPath(path)
      check parsed.isOk
      let res = handleSessionActionRequest(
        fakeAction, parsed.get(), """{"action":"new"}""", authorized(), Token)
      check res.status == 404
      check actionCalls == 1
      check lastRaw == uid
      check not lastRaw.startsWith("api:")

    test "403 when the user is revoked":
      resetAction()
      actionOutcome = gsaoRevoked
      let res = handleSessionActionRequest(
        fakeAction, "revoked-user", """{"action":"new"}""", authorized(), Token)
      check res.status == 403
      check actionCalls == 1

    test "400 for an unknown action body and the hook never runs":
      resetAction()
      for body in ["""{"kind":"reset"}""", """{"action":"reset"}""",
                   """{"action":"sk-fake"}"""]:
        resetAction()
        let res = handleSessionActionRequest(
          fakeAction, "user-1", body, authorized(), Token)
        check res.status == 400
        check actionCalls == 0

    test "401 without a token and the hook never runs":
      resetAction()
      for header in ["", "Bearer wrong"]:
        resetAction()
        let res = handleSessionActionRequest(
          fakeAction, "user-1", """{"action":"new"}""", header, Token)
        check res.status == 401
        check actionCalls == 0

    test "503 when the action hook is not wired":
      let res = handleSessionActionRequest(
        nil, "user-1", """{"action":"new"}""", authorized(), Token)
      check res.status == 503

    test "redacts secrets echoed by the error path":
      for secretBody in ["""{"action":"sk-fake"}""",
                         """{"action":"key=abc"}""",
                         """{"action":"Bearer x"}"""]:
        resetAction()
        let res = handleSessionActionRequest(
          fakeAction, "user-1", secretBody, authorized(), Token)
        check res.status == 400
        check not res.body.contains("sk-fake")
        check not res.body.contains("key=abc")
        check not res.body.contains("Bearer x")

  suite "dashboard shell":

    test "carries the sessions and providers tables plus the new-conversation button":
      let html = buildDashboardHtml()
      check html.count("<table") >= 2
      check html.contains("id=\"sessions\"")
      check html.contains("id=\"providers\"")
      check html.toLowerAscii().contains("nova conversa")
      check html.contains("/api/sessions")
      check html.contains("/api/providers")
      check html.contains("Authorization: 'Bearer '")
      check html.contains("setInterval")

    test "keeps the CSP locked to default-src 'none'":
      let html = buildDashboardHtml()
      check html.contains("default-src 'none'")
      check html.contains("Content-Security-Policy")

    test "has no inline data, no inline handler and no embedded token":
      let html = buildDashboardHtml()
      check not html.contains("onclick=")
      check not html.contains("sk-")
      check not html.contains("Bearer sk-")
      check not html.contains("DONKEY_HTTP_TOKEN=")
      check not html.contains("<script src=")

when isMainModule:
  runTests()
