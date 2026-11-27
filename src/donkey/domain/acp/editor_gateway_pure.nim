## editor_gateway_pure — the bodies of the gateway's editor routes (E10.2).
##
##   POST /v1/acp/pair             {"name"}     → {"code","pairing","expiresIn","confirmWith"}
##   POST /v1/acp/pair/poll        {"pairing"}  → 202 pending | 200 {"token"} once | 404
##   POST /v1/acp/chat/completions (Bearer <editor token>) → the OpenAI stream,
##                                 as the person the editor was paired with

import std/json
import ../../core/pipeops
import ./editor_pairing_pure

const MaxEditorRequestBytes* = 4096

proc parsePairRequest*(body: string): Result[string, string] =
  ## The editor's name ("" when the body is empty: shown as "editor").
  if body.len == 0: return ok("")
  try:
    let j = parseJson(body)
    if j.kind != JObject: return err("expected a JSON object")
    ok(j{"name"}.getStr)
  except CatchableError as e:
    err("invalid JSON: " & e.msg)

proc parsePollRequest*(body: string): Result[string, string] =
  try:
    let j = parseJson(body)
    if j.kind != JObject: return err("expected a JSON object")
    let secret = j{"pairing"}.getStr
    if secret.len == 0: return err("missing 'pairing'")
    ok(secret)
  except CatchableError as e:
    err("invalid JSON: " & e.msg)

proc pairStartedBody*(code, secret: string; expiresInSec: int): JsonNode =
  %* {"code": code, "pairing": secret, "expiresIn": expiresInSec,
      "confirmWith": "/editor " & code}

proc pollReply*(state: EditorPairingState; token: string): tuple[status: int, body: JsonNode] =
  case state
  of epsPending: (status: 202, body: %* {"status": "pending"})
  of epsConfirmed: (status: 200, body: %* {"status": "paired", "token": token})
  of epsUnknown: (status: 404, body: %* {"status": "unknown",
                  "error": "no such pairing, or it expired; pair again"})
