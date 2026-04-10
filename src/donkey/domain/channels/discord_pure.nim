## discord_pure.nim — pure parsing of Discord gateway dispatch payloads.
##
## No I/O, no side effects. All parsing functions are `func`.
##
## Topology (pipeops):
##   |>    — unary pure transform  (d |> extractDiscordUser)
##   |>->  — last-arg pipe         (opts |>-> findOption(name))
##   >>=   — Result chain          (parseResult >>= validateContent)
##
## Contract:
##   1. parseDispatch(t, d)         → DsParseResult   (single dispatch event)
##   2. toInbound(r, userId)        → InboundMessage
##   3. hasInteraction(r)           → bool             (interaction needs ack)

import std/json
import ../../core/pipeops
import ../../domain/message

# ── Domain types ──────────────────────────────────────────────────────────────

type
  DsEventKind* = enum
    dekMessage       ## MESSAGE_CREATE — regular DM or guild message
    dekSlashCommand  ## INTERACTION_CREATE type 2 — application command
    dekButtonClick   ## INTERACTION_CREATE type 3 — component button click
    dekModalSubmit   ## INTERACTION_CREATE type 5 — modal form submit
    dekUnknown       ## unsupported or filtered (bot message, empty, etc.)

  DsParseResult* = object
    kind*:             DsEventKind
    rawId*:            string   ## discord_user_id (before identity resolution)
    content*:          string   ## message text or synthesised command text
    channelId*:        string   ## Discord channel ID (for MESSAGE_CREATE)
    messageId*:        string   ## Discord message ID
    interactionId*:    string   ## interaction ID (non-empty for interactions)
    interactionToken*: string   ## interaction token (non-empty for interactions)
    needsModal*:       bool     ## /continue without code → caller must send modal

# ── Internal pure helpers ─────────────────────────────────────────────────────

func extractDiscordUser(d: JsonNode): string =
  ## Returns the discord user id from a dispatch payload.
  ## Checks top-level "user" first, then "member.user" (guild context).
  let userNode =
    if d.hasKey("user"):   d["user"]
    elif d.hasKey("member") and d["member"].hasKey("user"): d["member"]["user"]
    else: nil
  if userNode == nil: "" else: userNode.getOrDefault("id").getStr("")

func findOption(name: string; opts: JsonNode): string =
  ## Searches a Discord interaction options array for the named string value.
  ## Designed for  opts |>-> findOption(name)  (piped value is last arg).
  if opts == nil or opts.kind != JArray: return ""
  for opt in opts:
    if opt.getOrDefault("name").getStr("") == name:
      return opt.getOrDefault("value").getStr("")
  ""

func extractModalCode(d: JsonNode): string =
  ## Extracts the "link_code" text-input value from a MODAL_SUBMIT payload.
  let components = d.getOrDefault("data").getOrDefault("components")
  if components == nil or components.kind != JArray: return ""
  for row in components:
    let rowComps = row.getOrDefault("components")
    if rowComps != nil and rowComps.kind == JArray:
      for comp in rowComps:
        if comp.getOrDefault("custom_id").getStr("") == "link_code":
          return comp.getOrDefault("value").getStr("")
  ""

func parseMessageCreate(d: JsonNode): DsParseResult =
  ## Parses a MESSAGE_CREATE dispatch payload.
  let author = d.getOrDefault("author")
  if author == nil: return DsParseResult(kind: dekUnknown)
  if author.getOrDefault("bot").getBool(false): return DsParseResult(kind: dekUnknown)
  let content = d.getOrDefault("content").getStr("")
  if content.len == 0: return DsParseResult(kind: dekUnknown)
  DsParseResult(
    kind:      dekMessage,
    rawId:     author.getOrDefault("id").getStr(""),
    content:   content,
    channelId: d.getOrDefault("channel_id").getStr(""),
    messageId: d.getOrDefault("id").getStr(""),
  )

func buildSlashContent(cmdName: string; iData: JsonNode): string =
  ## Assembles the command string from a slash command interaction.
  let opts = iData.getOrDefault("options")
  case cmdName
  of "models":
    let provider = opts |>-> findOption("provider")
    let model    = opts |>-> findOption("model")
    if provider.len > 0 and model.len > 0: "/models " & provider & " " & model
    elif provider.len > 0:                 "/models " & provider
    else:                                  "/models"
  of "think":
    let level = opts |>-> findOption("level")
    if level.len > 0: "/think " & level else: "/think"
  of "budget":
    let policy = opts |>-> findOption("policy")
    if policy.len > 0: "/budget " & policy else: "/budget"
  else:
    "/" & cmdName

func parseApplicationCommand(d: JsonNode;
                             interactionId, interactionToken,
                             userId: string): DsParseResult =
  ## Parses an APPLICATION_COMMAND interaction (type 2).
  let iData = d.getOrDefault("data")
  if iData == nil: return DsParseResult(kind: dekUnknown)
  let cmdName = iData.getOrDefault("name").getStr("")
  if cmdName == "continue":
    let opts = iData.getOrDefault("options")
    let code = opts |>-> findOption("code")
    if code.len > 0:
      return DsParseResult(
        kind:             dekSlashCommand,
        rawId:            userId,
        content:          code,
        interactionId:    interactionId,
        interactionToken: interactionToken,
      )
    else:
      return DsParseResult(
        kind:             dekSlashCommand,
        rawId:            userId,
        interactionId:    interactionId,
        interactionToken: interactionToken,
        needsModal:       true,
      )
  DsParseResult(
    kind:             dekSlashCommand,
    rawId:            userId,
    content:          buildSlashContent(cmdName, iData),
    interactionId:    interactionId,
    interactionToken: interactionToken,
  )

func parseInteractionCreate(d: JsonNode): DsParseResult =
  ## Parses an INTERACTION_CREATE dispatch payload.
  let interactionType  = d.getOrDefault("type").getInt(0)
  let interactionId    = d.getOrDefault("id").getStr("")
  let interactionToken = d.getOrDefault("token").getStr("")
  let userId           = d |> extractDiscordUser
  if userId.len == 0: return DsParseResult(kind: dekUnknown)

  if interactionType == 2:
    return parseApplicationCommand(d, interactionId, interactionToken, userId)

  if interactionType == 3:
    let customId = d.getOrDefault("data").getOrDefault("custom_id").getStr("")
    let messageId = d.getOrDefault("message").getOrDefault("id").getStr("")
    return DsParseResult(
      kind:             dekButtonClick,
      rawId:            userId,
      content:          customId,
      messageId:        messageId,
      interactionId:    interactionId,
      interactionToken: interactionToken,
    )

  if interactionType == 5:
    let code = d |> extractModalCode
    return DsParseResult(
      kind:             dekModalSubmit,
      rawId:            userId,
      content:          code,
      interactionId:    interactionId,
      interactionToken: interactionToken,
    )

  DsParseResult(kind: dekUnknown)

# ── Public pure API ───────────────────────────────────────────────────────────

func parseDispatch*(t: string; d: JsonNode): DsParseResult =
  ## Parses a Discord gateway op=0 dispatch event into a DsParseResult.
  ## Returns dekUnknown for unhandled event types or filtered messages.
  ##
  ## Usage:  let r = parseDispatch(t, d)
  case t
  of "MESSAGE_CREATE":    d |> parseMessageCreate
  of "INTERACTION_CREATE": d |> parseInteractionCreate
  else:                    DsParseResult(kind: dekUnknown)

func toInbound*(r: DsParseResult; userId: UserId): InboundMessage =
  ## Converts a DsParseResult + resolved UserId into an InboundMessage.
  InboundMessage(
    userId:    userId,
    channel:   ckDiscord,
    channelId: r.channelId,
    messageId: r.messageId,
    text:      r.content,
  )

func hasInteraction*(r: DsParseResult): bool =
  ## True when the result carries an interaction that requires an HTTP ack.
  r.interactionId.len > 0
