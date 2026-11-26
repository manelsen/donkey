## `/webhook/google-chat` on the shared receiver (second round, front 1):
## only an event carrying a token Chat signed for this project reaches the
## queue. Tokens here are minted with a throwaway key whose public half is
## seeded as Google's keys.

import std/[json, tables, times, unittest]
import donkey/core/pipeops
import donkey/adapters/channel/google_chat
import donkey/adapters/webhook/webhook_ingress
import donkey/adapters/webhook/webhook_receiver
import ../channel/google_chat_vectors

let now = getTime().toUnix
let cfg = WebhookConfig(googleChatProjectNumber: "123456789")

proc event(): string =
  $(%* {"type": "MESSAGE",
        "message": {"name": "spaces/S1/messages/M1",
                    "sender": {"name": "users/111", "displayName": "Belle", "type": "HUMAN"},
                    "text": "oi", "thread": {"name": "spaces/S1/threads/T1"},
                    "space": {"name": "spaces/S1", "type": "DM"}}})

proc request(token: string; httpMethod = "POST"): WebhookRequest =
  var headers = initTable[string, string]()
  if token.len > 0: headers["authorization"] = "Bearer " & token
  WebhookRequest(httpMethod: httpMethod, path: GoogleChatPath, headers: headers, body: event())

proc good(aud = "123456789"; iss = ChatIssuer): string =
  mintToken(%* {"iss": iss, "aud": aud, "iat": now - 5, "exp": now + 300})

proc drain(): int =
  while tryRecvChatEvent()[0]: inc result

proc runTests*() =
  suite "webhook google chat":
    setup:
      discard drain()
      resetChatKeys()
      seedChatKeys(TestJwks, getTime().toUnix * 1000)

    test "a token Chat signed for this project: queued, answered at once":
      let r = handleWebhookRequest(cfg, request(good()))
      check r.status == 200
      check drain() == 1

    test "no token, another project, another issuer or another key: 401, nothing queued":
      check handleWebhookRequest(cfg, request("")).status == 401
      check handleWebhookRequest(cfg, request(good(aud = "999"))).status == 401
      check handleWebhookRequest(cfg, request(good(iss = "x@y"))).status == 401
      check handleWebhookRequest(cfg, request(mintToken(%* {"iss": ChatIssuer,
        "aud": "123456789", "iat": now, "exp": now + 300}, kid = "other"))).status == 401
      check drain() == 0

    test "the route is closed without a project number; only POST":
      check handleWebhookRequest(WebhookConfig(), request(good())).status == 404
      check handleWebhookRequest(cfg, request(good(), httpMethod = "GET")).status == 405

when isMainModule:
  runTests()
