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

import std/[json, strutils]
import ../../core/pipeops
import ../../domain/message

const
  DiscordMaxInboundAttachmentBytes* = 25 * 1024 * 1024
    ## Larger attachments are never downloaded (the whole body is held in
    ## memory); the turn gets a note naming the file instead.

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
    hasMedia*:         bool     ## true when message has attachments
    attachmentUrls*:   seq[string]  ## list of attachment URLs (proxy_url or url)
    guildId*:          string   ## server id; empty for a DM
    referencedAuthorId*: string ## author of the message this one replies to

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

func isBotAuthored*(msg: JsonNode): bool =
  ## A bot account, or a webhook post: a webhook's author carries no `bot`
  ## flag, `webhook_id` is what marks it (hermes 68276773cf).
  let author = msg.getOrDefault("author")
  if author != nil and author.getOrDefault("bot").getBool(false):
    return true
  let webhook = msg.getOrDefault("webhook_id")
  webhook != nil and webhook.kind == JString and webhook.getStr.len > 0

func withSafeMentions*(body: JsonNode): JsonNode =
  ## Every message body the bot sends: users can be mentioned, but never
  ## @everyone/@here or a role (hermes efa6c9f715). The text is the model's,
  ## so a mention in it is not an operator's decision.
  result = body.copy()
  result["allowed_mentions"] = %* {"parse": ["users"]}

func oversizeNote(fileName: string; size: BiggestInt): string =
  "[Anexo " & fileName & " ignorado: " & $size &
    " bytes, acima do limite de " & $(DiscordMaxInboundAttachmentBytes div
    (1024 * 1024)) & " MiB.]"

func parseMessageCreate(d: JsonNode): DsParseResult =
  ## Parses a MESSAGE_CREATE dispatch payload.
  let author = d.getOrDefault("author")
  if author == nil: return DsParseResult(kind: dekUnknown)
  if isBotAuthored(d): return DsParseResult(kind: dekUnknown)
  var content = d.getOrDefault("content").getStr("")

  # Extract attachments if present; an oversize one is named, not fetched.
  var attachmentUrls: seq[string] = @[]
  var notes: seq[string] = @[]
  let attachments = d.getOrDefault("attachments")
  if attachments != nil and attachments.kind == JArray:
    for att in attachments:
      let size = att.getOrDefault("size").getBiggestInt(0)
      if size > DiscordMaxInboundAttachmentBytes:
        notes.add(oversizeNote(att.getOrDefault("filename").getStr("?"), size))
        continue
      # Use proxy_url if available, fallback to url
      let url = att.getOrDefault("proxy_url").getStr(att.getOrDefault("url").getStr(""))
      if url.len > 0:
        attachmentUrls.add(url)
  let hasMedia = attachmentUrls.len > 0
  if notes.len > 0:
    if content.len > 0: content.add("\n\n")
    content.add(notes.join("\n"))

  # Allow messages with attachments even if content is empty
  if content.len == 0 and not hasMedia:
    return DsParseResult(kind: dekUnknown)

  DsParseResult(
    kind:      dekMessage,
    rawId:     author.getOrDefault("id").getStr(""),
    content:   content,
    channelId: d.getOrDefault("channel_id").getStr(""),
    messageId: d.getOrDefault("id").getStr(""),
    hasMedia:  hasMedia,
    attachmentUrls: attachmentUrls,
    guildId:   d.getOrDefault("guild_id").getStr(""),
    referencedAuthorId:
      d.getOrDefault("referenced_message").getOrDefault("author")
        .getOrDefault("id").getStr(""),
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

# ── Mentions ──────────────────────────────────────────────────────────────────

func mentionForms(botId: string): array[2, string] =
  ["<@" & botId & ">", "<@!" & botId & ">"]

func addressesBot*(content, botId, referencedAuthorId: string): bool =
  ## A server message is for the bot when it carries the bot's raw mention or
  ## replies to one of the bot's messages (hermes 608e8a6062). The `mentions`
  ## array is not used: a reply ping puts the replied-to author there without
  ## any mention in the text (hermes e9bceb5ae0).
  if botId.len == 0: return false
  if referencedAuthorId == botId: return true
  for form in mentionForms(botId):
    if form in content: return true
  false

func stripBotMention*(content, botId: string): string =
  ## The text without the bot's mentions, so "<@bot> /help" is the command
  ## "/help". Spacing left by the removal is collapsed line by line, so a
  ## multi-line message keeps its lines. Only the mention comes back empty.
  if botId.len == 0: return content
  var lines: seq[string]
  for line in content.splitLines():
    var cleaned = line
    for form in mentionForms(botId):
      cleaned = cleaned.replace(form, "")
    lines.add(if cleaned == line: line else: cleaned.splitWhitespace().join(" "))
  lines.join("\n").strip()

# ── Outbound text ─────────────────────────────────────────────────────────────

func tableCells(line: string): seq[string] =
  var body = line.strip()
  if body.startsWith("|"): body = body[1 .. ^1]
  if body.endsWith("|"): body = body[0 ..< ^1]
  for cell in body.split('|'):
    result.add(cell.strip())

func isTableRow(line: string): bool =
  '|' in line and line.strip().len > 0

func isSeparatorRow(line: string): bool =
  ## `|---|:-:|--:|`: every cell is dashes with optional alignment colons.
  if not line.isTableRow: return false
  let cells = tableCells(line)
  if cells.len == 0: return false
  for cell in cells:
    let core = cell.strip(chars = {':'})
    if core.len == 0 or core.strip(chars = {'-'}).len != 0:
      return false
  true

func rowAsBullets(headers, cells: seq[string]): string =
  ## First column is the heading; every other non-empty cell is a bullet
  ## labelled by its column header.
  var lines: seq[string]
  if cells.len > 0 and cells[0].len > 0:
    lines.add("**" & cells[0] & "**")
  for i in 1 ..< cells.len:
    if cells[i].len == 0: continue
    let label = if i < headers.len and headers[i].len > 0: headers[i]
                else: "Col " & $(i + 1)
    lines.add("• " & label & ": " & cells[i])
  lines.join("\n")

func discordText*(text: string): string =
  ## Discord does not render GFM pipe tables (hermes cf7bf5bdc9): each table
  ## becomes one block per row, the first cell in bold and the other cells as
  ## `• Header: value`. Fenced code is left as it is.
  let lines = text.split('\n')
  var output: seq[string]
  var inFence = false
  var i = 0
  while i < lines.len:
    let line = lines[i]
    if line.strip().startsWith("```"):
      ## "```x```" opens and closes on the same line.
      if line.count("```") mod 2 == 1:
        inFence = not inFence
      output.add(line)
      inc i
      continue
    if not inFence and line.isTableRow and i + 1 < lines.len and
        lines[i + 1].isSeparatorRow and not line.isSeparatorRow:
      let headers = tableCells(line)
      var blocks: seq[string]
      i += 2
      ## The last two conditions stop at the header of a next table placed
      ## right below this one.
      while i < lines.len and lines[i].isTableRow and
          not lines[i].strip().startsWith("```") and
          not lines[i].isSeparatorRow and
          not (i + 1 < lines.len and lines[i + 1].isSeparatorRow):
        let rendered = rowAsBullets(headers, tableCells(lines[i]))
        if rendered.len > 0: blocks.add(rendered)
        inc i
      if blocks.len > 0:
        output.add(blocks.join("\n\n"))
      continue
    output.add(line)
    inc i
  output.join("\n")

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
  ## If hasMedia is true, first attachment URL is placed in mediaUrl.
  var mediaUrl = ""
  if r.hasMedia and r.attachmentUrls.len > 0:
    mediaUrl = r.attachmentUrls[0]

  InboundMessage(
    userId:    userId,
    channel:   ckDiscord,
    channelId: r.channelId,
    messageId: r.messageId,
    text:      r.content,
    mediaUrl:  mediaUrl,
  )

func hasInteraction*(r: DsParseResult): bool =
  ## True when the result carries an interaction that requires an HTTP ack.
  r.interactionId.len > 0
