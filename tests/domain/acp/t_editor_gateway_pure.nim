## The gateway's editor routes (E10.2): they never take the operator's token;
## pairing authenticates by its secret, the chat by the editor's credential.

import std/[json, unittest]
import donkey/core/pipeops
import donkey/domain/gateway/auth_pure
import donkey/domain/gateway/routing_pure
import donkey/domain/acp/editor_pairing_pure
import donkey/domain/acp/editor_gateway_pure

proc runTests*() =
  suite "editor routes":
    test "the routes, outside /api, and authenticated by the handler":
      check routeGatewayRequest(GatewayRequest(meth: "POST", path: "/v1/acp/pair")) == "acp_pair"
      check routeGatewayRequest(GatewayRequest(meth: "POST", path: "/v1/acp/pair/poll")) == "acp_pair_poll"
      check routeGatewayRequest(GatewayRequest(meth: "POST", path: "/v1/acp/chat/completions")) == "acp_chat"
      check routeGatewayRequest(GatewayRequest(meth: "POST", path: "/v1/acp/approve")) == "acp_approve"
      check routeGatewayRequest(GatewayRequest(meth: "POST", path: "/v1/acp/editor_result")) == "acp_editor_result"
      for action in ["acp_pair", "acp_pair_poll", "acp_chat", "acp_approve", "acp_editor_result"]:
        check not isApiRouteAction(action)
        check gatewayAuthVerdict(action, "", "operator-secret") == gavEditor
        check gatewayAuthVerdict(action, "Bearer operator-secret", "operator-secret") == gavEditor

    test "asking to pair: the editor's name; the answer: the code, the secret, the wait":
      check parsePairRequest("""{"name":"Zed"}""").get == "Zed"
      check parsePairRequest("").get == ""
      check parsePairRequest("[1]").isErr
      let body = pairStartedBody("K7QP2M", "sec", 600)
      check body == %* {"code": "K7QP2M", "pairing": "sec", "expiresIn": 600,
                        "confirmWith": "/editor K7QP2M"}

    test "polling: the secret in; pending, the token once, or gone":
      check parsePollRequest("""{"pairing":"sec"}""").get == "sec"
      check parsePollRequest("""{"pairing":""}""").isErr
      check parsePollRequest("{}").isErr
      check pollReply(epsPending, "") == (status: 202, body: %* {"status": "pending"})
      check pollReply(epsConfirmed, "tok") == (status: 200, body: %* {"status": "paired", "token": "tok"})
      check pollReply(epsUnknown, "").status == 404

proc runApproveTests*() =
  suite "editor routes — an approval answered from the editor (E10.4)":
    test "only an approval's callback is accepted":
      check parseApproveRequest("""{"callback":"approval:abc:allow"}""").get == "approval:abc:allow"
      check parseApproveRequest("""{"callback":"approval:abc:always"}""").get == "approval:abc:always"
      check parseApproveRequest("""{"callback":"/reset"}""").isErr
      check parseApproveRequest("""{"callback":""}""").isErr
      check parseApproveRequest("[]").isErr

proc runEditorResultTests*() =
  suite "editor routes — the editor's answer to a request (E10.5)":
    test "the request id, and the content or the error":
      check parseEditorResult("""{"id":"ef-1","content":"echo 1"}""").get ==
        (id: "ef-1", content: "echo 1", error: "")
      check parseEditorResult("""{"id":"ef-1","error":"no such file"}""").get.error == "no such file"
      check parseEditorResult("""{"content":"x"}""").isErr
      check parseEditorResult("[]").isErr

when isMainModule:
  runTests()
  runApproveTests()
  runEditorResultTests()
