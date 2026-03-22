## Identity domain — pure functions for cross-channel identity mapping.
##
## Maps (ChannelKind, rawId) pairs to/from storage keys.
## UUID generation and file persistence live in the adapter layer.
##
## Designed for pipeops topology:
##   rawId |>-> channelKey(ckTelegram)          -- |>-> last-arg pipe
##   "12345" |> validateRawId                   -- |> unary pipe
##   parseChannelKey(key) >>= validatePair       -- >>= Result chain

import std/strutils
import ../core/types
import ../core/pipeops

# ── Storage key format ────────────────────────────────────────────────────────

func channelKey*(kind: ChannelKind; rawId: string): string =
  ## Formats a storage key: "telegram:12345" or "discord:678901234".
  ## rawId is the last arg, so: rawId |>-> channelKey(ckTelegram)
  $kind & ":" & rawId

# ── Channel kind parsing ──────────────────────────────────────────────────────

func parseChannelKind*(s: string): Result[ChannelKind, string] =
  ## Parses a channel kind string into a ChannelKind enum value.
  case s
  of "telegram": ok(ckTelegram)
  of "discord":  ok(ckDiscord)
  of "wecom":    ok(ckWeCom)
  of "wechat":   ok(ckWeChat)
  of "qq":       ok(ckQQ)
  of "feishu":   ok(ckFeishu)
  else: err("unknown channel kind: " & s)

# ── Key parsing ───────────────────────────────────────────────────────────────

func parseChannelKey*(key: string): Result[(ChannelKind, string), string] =
  ## Parses a storage key into (ChannelKind, rawId).
  ## Errors on missing colon, empty rawId, or unknown channel.
  let idx = key.find(':')
  if idx < 0:
    return err("missing ':' in channel key: " & key)
  let kindStr = key[0 ..< idx]
  let rawId   = key[idx + 1 .. ^1]
  if rawId.len == 0:
    return err("empty rawId in channel key: " & key)
  let kind = ? parseChannelKind(kindStr)
  ok((kind, rawId))

# ── RawId validation ──────────────────────────────────────────────────────────

func validateRawId*(rawId: string): Result[string, string] =
  ## Validates that a raw channel user ID is non-empty.
  ## Designed for |> and >>= chaining.
  if rawId.len == 0:
    err("rawId must not be empty")
  else:
    ok(rawId)

# ── Link code validation ──────────────────────────────────────────────────────

const
  LinkCodeAlpha* = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  LinkCodeLen*   = 6

func isValidLinkCode*(code: string): bool =
  ## Returns true if code is a valid 6-char link code (uppercase, no ambiguous chars).
  ## Designed for |> chaining.
  if code.len != LinkCodeLen: return false
  for c in code:
    if c notin LinkCodeAlpha: return false
  true

func validateLinkCode*(code: string): Result[string, string] =
  ## Result-wrapper around isValidLinkCode, for >>= chaining.
  if isValidLinkCode(code):
    ok(code)
  else:
    err("invalid link code: " & code)
