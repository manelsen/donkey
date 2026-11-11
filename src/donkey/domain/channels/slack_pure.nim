## slack_pure.nim — pure parsing of Slack Events API webhook payloads.
##
## No I/O, no side effects. All parsing functions are `func`.
##
## Topology (pipeops):
##   |>    — unary pure transform  (payload |> parseEvent)
##   |>->  — last-arg pipe         (node |>-> extractField("user"))
##   >>=   — Result chain          (parseResult >>= validateContent)
##
## Contract:
##   1. parseEvent(JsonNode)        → SlkParseResult   (single event payload)
##   2. toInbound(r, userId)        → InboundMessage
##   3. isVerification(r)           → bool             (url_verification challenge)

import std/[json, strutils]
import ../../core/pipeops
import ../../domain/message

# ── Domain types ──────────────────────────────────────────────────────────────

type
  SlkEventKind* = enum
    sekMessage      ## event_callback + event.type in ["message","app_mention"]
    sekSlashCommand ## type="slash_command" (pre-parsed to JSON by adapter)
    sekBlockAction  ## type="block_actions" interactive payload
    sekVerification ## type="url_verification" — challenge response required
    sekUnknown      ## unsupported or filtered event

  SlkParseResult* = object
    kind*:        SlkEventKind
    rawId*:       string   ## Slack user id (U...) before identity resolution
    text*:        string   ## message text or command + args
    channelId*:   string   ## Slack channel id (C...)
    teamId*:      string   ## Slack workspace/team id (T...)
    eventId*:     string   ## Events API event_id, used for deduplication
    eventTs*:     string   ## event timestamp (ts field, used as channelId dedup)
    responseUrl*: string   ## response_url for slash commands / block actions
    triggerId*:   string   ## trigger_id (non-empty when modal can be opened)
    challenge*:   string   ## challenge value for url_verification

# ── Internal pure helpers ─────────────────────────────────────────────────────

func extractField(name: string; node: JsonNode): string =
  ## Returns a string field from a JsonNode by name.
  ## Designed for  node |>-> extractField(name)  (piped value is last arg).
  if node == nil: return ""
  node.getOrDefault(name).getStr("")

func extractUserId(event: JsonNode): string =
  ## Extracts a user id from an event sub-object.
  ## Tries "user" (string), then "user.id" (object form used in block_actions).
  if event == nil: return ""
  let userField = event.getOrDefault("user")
  if userField == nil: return ""
  case userField.kind
  of JString: userField.getStr("")
  of JObject: userField.getOrDefault("id").getStr("")
  else: ""

func parseMessageEvent(teamId, eventId: string; event: JsonNode): SlkParseResult =
  ## Parses a "message" or "app_mention" event sub-object.
  ## Designed for  event |>-> parseMessageEvent(teamId)  (piped value is last arg).
  let userId = event |> extractUserId
  if userId.len == 0: return SlkParseResult(kind: sekUnknown)
  let text = event |>-> extractField("text")
  if text.len == 0: return SlkParseResult(kind: sekUnknown)
  ## Filter out bot_id messages (posted by bots/apps).
  let botId = event |>-> extractField("bot_id")
  if botId.len > 0: return SlkParseResult(kind: sekUnknown)
  ## Subtype "bot_message" also indicates a bot posting.
  let subtype = event |>-> extractField("subtype")
  if subtype == "bot_message": return SlkParseResult(kind: sekUnknown)
  SlkParseResult(
    kind:      sekMessage,
    rawId:     userId,
    text:      text,
    channelId: event |>-> extractField("channel"),
    teamId:    teamId,
    eventId:   eventId,
    eventTs:   event |>-> extractField("ts"),
  )

func parseSlashCommand(payload: JsonNode): SlkParseResult =
  ## Parses a slash command payload (already as JsonNode by the adapter).
  ## Slack sends slash command payloads as form-encoded; adapter converts to JSON.
  let userId = payload |>-> extractField("user_id")
  if userId.len == 0: return SlkParseResult(kind: sekUnknown)
  let command = payload |>-> extractField("command")
  let args    = payload |>-> extractField("text")
  let text    = if args.len > 0: command & " " & args else: command
  SlkParseResult(
    kind:        sekSlashCommand,
    rawId:       userId,
    text:        text,
    channelId:   payload |>-> extractField("channel_id"),
    teamId:      payload |>-> extractField("team_id"),
    responseUrl: payload |>-> extractField("response_url"),
    triggerId:   payload |>-> extractField("trigger_id"),
  )

func parseBlockActions(payload: JsonNode): SlkParseResult =
  ## Parses a block_actions interactive payload.
  let userId = payload |> extractUserId
  if userId.len == 0: return SlkParseResult(kind: sekUnknown)
  let actions = payload.getOrDefault("actions")
  let actionId =
    if actions != nil and actions.kind == JArray and actions.len > 0:
      actions[0].getOrDefault("action_id").getStr("")
    else: ""
  let actionValue =
    if actions != nil and actions.kind == JArray and actions.len > 0:
      let v = actions[0].getOrDefault("value")
      if v != nil: v.getStr("") else: ""
    else: ""
  ## Adapters may set action_id == value (single data payload). Avoid
  ## duplicating it as "data:data"; the runtime maps the data to a command.
  let content =
    if actionValue.len > 0 and actionValue != actionId: actionId & ":" & actionValue
    elif actionValue.len > 0: actionValue
    else: actionId
  let channel = payload.getOrDefault("channel")
  let channelId =
    if channel != nil and channel.kind == JObject:
      channel.getOrDefault("id").getStr("")
    else: ""
  SlkParseResult(
    kind:        sekBlockAction,
    rawId:       userId,
    text:        content,
    channelId:   channelId,
    teamId:      payload |>-> extractField("team_id"),
    responseUrl: payload |>-> extractField("response_url"),
    triggerId:   payload |>-> extractField("trigger_id"),
  )

# ── Public pure API ───────────────────────────────────────────────────────────

func parseEvent*(payload: JsonNode): SlkParseResult =
  ## Parses a Slack Events API webhook payload into a SlkParseResult.
  ## Returns sekUnknown for unhandled event types or filtered messages.
  ##
  ## Usage:  let r = payload |> parseEvent
  if payload == nil: return SlkParseResult(kind: sekUnknown)
  let payloadType = payload |>-> extractField("type")
  case payloadType
  of "url_verification":
    let ch = payload |>-> extractField("challenge")
    SlkParseResult(kind: sekVerification, challenge: ch)
  of "event_callback":
    let event   = payload.getOrDefault("event")
    if event == nil: return SlkParseResult(kind: sekUnknown)
    let evType  = event |>-> extractField("type")
    let teamId  = payload |>-> extractField("team_id")
    let eventId = payload |>-> extractField("event_id")
    if evType in ["message", "app_mention"]:
      event |>-> parseMessageEvent(teamId, eventId)
    else:
      SlkParseResult(kind: sekUnknown)
  of "slash_command":
    payload |> parseSlashCommand
  of "block_actions":
    payload |> parseBlockActions
  else:
    SlkParseResult(kind: sekUnknown)

func toInbound*(r: SlkParseResult; userId: UserId): InboundMessage =
  ## Converts a SlkParseResult + resolved UserId into an InboundMessage.
  InboundMessage(
    userId:    userId,
    channel:   ckSlack,
    channelId: r.eventTs,
    text:      r.text,
  )

func isVerification*(r: SlkParseResult): bool =
  ## True when the payload is a url_verification challenge that needs echoing back.
  r.kind == sekVerification

func blockActionCommand*(data: string): string =
  ## Maps a Slack block action payload (`action_id:value` from
  ## `parseBlockActions`) to the equivalent text command. Returns "" for
  ## actions that have no textual command equivalent.
  if data.len == 0:
    return ""
  case data
  of "models":    return "/models"
  of "think":     return "/think"
  of "budget":    return "/budget"
  of "help":      return "/help"
  of "status":    return "/status"
  of "doctor":    return "/doctor"
  of "forget":    return "/forget"
  of "reset":     return "/reset"
  of "mycode":    return "/mycode"
  of "reasoning": return "/reasoning"
  of "menu":      return "/menu"
  of "config":    return "/config"
  of "models:back": return "/menu"
  else: discard

  if data.startsWith("models:provider:"):
    return "/models " & data[16 .. ^1]
  if data.startsWith("models:set:"):
    let parts = data[11 .. ^1].split(':')
    if parts.len >= 2 and parts[0].len > 0 and parts[1].len > 0:
      return "/models " & parts[0] & " " & parts[1]
    return "/models"
  if data.startsWith("models:page:"):
    let rest = data[12 .. ^1]
    let idx = rest.rfind(':')
    if idx > 0:
      return "/models " & rest[0 ..< idx]
    return "/models"
  if data.startsWith("think:set:"):
    return "/think " & data[10 .. ^1]
  if data.startsWith("help:page:"):
    return "/help"
  ""
