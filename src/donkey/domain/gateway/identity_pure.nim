## Pure identity rules for the agent-facing HTTP API.
##
## An API caller is mapped to a synthetic user id `api:<name>`. The name is
## validated here, before it ever becomes a session key: only a conservative
## alphabet is accepted so a caller cannot smuggle path separators or a second
## namespace prefix into storage.

import std/strutils
import results
import ../../core/types
import ../message

type
  AuthVerdict* = enum
    ## The ingress decision for an API user. Revocation wins over DM policy;
    ## the runtime maps `avRevoked`/`avNotAllowed` to 403 and never dispatches.
    avAllowed
    avRevoked
    avNotAllowed

  authorize* = proc(userId: UserId): AuthVerdict {.gcsafe, raises: [].}
    ## Policy injected by the ingress owner (`isRevoked` + DM policy).

  AuthorizeFn* = authorize

const
  ApiUserPrefix* = "api:"
  MaxApiUserLen* = 64

func isApiUserNameChar(c: char): bool =
  (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or
    c in {'.', '_', '-'}

func apiUserId*(raw: string): Result[UserId, string] =
  ## Sanitises a client-supplied `user` into `UserId("api:" & raw)`.
  ## Rejects empty names, `.`/`..`, slashes, whitespace, uppercase and names
  ## longer than 64 characters.
  if raw.len == 0:
    return err("user must not be empty")
  if raw.len > MaxApiUserLen:
    return err("user must be at most " & $MaxApiUserLen & " characters")
  if raw == "." or raw == "..":
    return err("user must not be a path segment")
  for c in raw:
    if not isApiUserNameChar(c):
      return err("user contains an invalid character: " & $c)
  ok(UserId(ApiUserPrefix & raw))

func isApiUserId*(userId: UserId): bool =
  ## True for the synthetic `api:<name>` identity namespace. Programmatic API
  ## callers are not interactive users and must never enter onboarding.
  ($userId).startsWith(ApiUserPrefix)

func isApiChatReply*(msg: OutboundMessage): bool =
  ## True only for replies that belong to the API namespace. Keyed on the
  ## user id alone: `replyTo`/`channelId` are routing hints, not identity.
  isApiUserId(msg.userId)
