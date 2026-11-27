## editor_credentials_pure — the credentials paired editors hold (E10.2).
##
## The editor keeps the token; the daemon keeps its SHA-256, the person the
## editor speaks for, the name the person confirmed and a public id to list
## and revoke it. A leaked state file gives no token.

import std/[json, strutils]
import nimcrypto/sha2
import ../../core/pipeops
import ../../core/types
import ../gateway/auth_pure   # constantTimeEq

type
  EditorCredential* = object
    id*:        string   ## public, for `ctl editor list|revoke`
    tokenHash*: string
    userId*:    UserId
    name*:      string
    createdMs*: int64

func tokenHash*(token: string): string =
  var ctx: sha256
  ctx.init()
  ctx.update(token)
  let digest = ctx.finish()
  ctx.clear()
  for b in digest.data: result.add b.toHex(2).toLowerAscii

func newEditorCredential*(token, id: string; userId: UserId; name: string;
                          createdMs: int64): EditorCredential =
  EditorCredential(id: id, tokenHash: tokenHash(token), userId: userId,
                   name: name, createdMs: createdMs)

func personFor*(creds: openArray[EditorCredential]; token: string): Result[UserId, string] =
  if token.len == 0: return err("no editor token")
  let wanted = tokenHash(token)
  for c in creds:
    if constantTimeEq(c.tokenHash, wanted): return ok(c.userId)
  err("unknown editor token")

func revoke*(creds: var seq[EditorCredential]; id: string): Result[void, string] =
  for i, c in creds:
    if c.id == id:
      creds.delete(i)
      return ok()
  err("no editor with id " & id)

proc encodeCredentials*(creds: openArray[EditorCredential]): JsonNode =
  var items = newJArray()
  for c in creds:
    items.add(%* {"id": c.id, "tokenHash": c.tokenHash, "userId": $c.userId,
                   "name": c.name, "createdMs": c.createdMs})
  %* {"version": 1, "editors": items}

proc decodeCredentials*(text: string): Result[seq[EditorCredential], string] =
  ## "" is no file yet: no editors.
  if text.strip.len == 0: return ok(newSeq[EditorCredential]())
  try:
    var creds: seq[EditorCredential]
    for e in parseJson(text){"editors"}.getElems:
      let c = EditorCredential(id: e{"id"}.getStr, tokenHash: e{"tokenHash"}.getStr,
                               userId: UserId(e{"userId"}.getStr), name: e{"name"}.getStr,
                               createdMs: e{"createdMs"}.getBiggestInt)
      if c.id.len == 0 or c.tokenHash.len != 64 or ($c.userId).len == 0:
        return err("editors file: an entry without id, hash or person")
      creds.add c
    ok(creds)
  except CatchableError as e:
    err("editors file unreadable: " & e.msg)
