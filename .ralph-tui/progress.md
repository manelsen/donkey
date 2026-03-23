# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

### `|>->` requires piped value as LAST parameter
When designing functions for use with `|>->`, the piped subject must be the **last** parameter.
`arr |>-> maxNextOffset(offset)` expands to `maxNextOffset(offset, arr)` — not `maxNextOffset(arr, offset)`.
UFCS (`arr.f(x)`) applies the receiver as the **first** argument, so `|>->` and UFCS have opposite conventions.

### Pure parsing in `domain/channels/`
Adapter parsing logic (JSON → domain types) can be factored into `domain/channels/<channel>_pure.nim` with all `func`.
The adapter then calls the pure parser and handles only side-effectful work (HTTP, file_id resolution, ack calls).

### `>>=` with inline closures requires `{.gcsafe, raises: [].}`
The `>>=` template (pipeops.nim) type-checks `f` as `proc(x: T): Result[U, E] {.gcsafe, raises: [].}`.
Inline anonymous procs without those annotations compile only when inferred as gcsafe (no GC global capture).
Safer pattern: define a named helper `proc myHelper(x: T): Result[U, E] {.gcsafe, raises: [].}` and call it from the inline closure, so the closure itself is trivially gcsafe.

### `HttpResponse` not re-exported by `std_http`
`adapters/http/std_http.nim` imports but does NOT export `HttpResponse` from `ports/http`.
Any adapter module that references `HttpResponse` in signatures must `import ../../ports/http` directly.

### `extractJsonStr` — safe JSON string extraction in `func`
Feishu's `message.content` is a JSON-encoded string nested inside an already-parsed `JsonNode`.
Calling `parseJson` from a `func` would fail because `parseJson` is a `proc` in stdlib.
Solution: implement `extractJsonStr(key, encoded)` — a pure string scanner that extracts a quoted
value from simple JSON objects (single level, string values) without any proc calls.
Designed for `|>->` with the encoded string as the last arg.
This pattern applies whenever a JSON field is itself a JSON-encoded string that must be parsed
inside a `func`.

---

## 2026-03-22 - US-029
- Implemented `src/donkey/domain/channels/matrix_pure.nim` — pure parser for Matrix Client-Server API events
- Implemented `src/donkey/adapters/channel/matrix.nim` — webhook-style adapter using matrix_pure
- Created `tests/channel/t_matrix.nim` with 32 tests covering identity, construction, event queue routing, and pure parser integration
- Updated `src/donkey/core/types.nim` — added `ckMatrix` to ChannelKind enum
- Updated `src/donkey/ports/channel.nim` — added `matrix*` field to OutboundChannelPorts
- Updated `src/donkey/adapters/channel/outbound_builder.nim` — added MatrixAdapter parameter and matrix port builder
- Updated `src/donkey/app/outbound_runtime.nim` — added ckMatrix to all case statements
- Updated `src/donkey/app/outbound_runtime.nim` — added ckMatrix to all case statements
- Updated `src/donkey/donkey.nim` — added `mx: MatrixAdapter` to DaemonAdapters, Matrix initialization, import, and buildOutboundPorts call

**What was implemented:**
- `MxParseResult` / `MxMsgKind` — pure domain types (mxkText, mxkImage, mxkAudio, mxkVideo, mxkFile, mxkUnknown)
- `parseEvent(JsonNode)` — parses Matrix events; handles m.text/m.notice/m.emote → mxkText; m.image/audio/video/file → media kinds; non-m.room.message → mxkUnknown
- Routing convention: rawId = room_id for all events (enables outbound sends via reverseChannel → room_id)
- `MatrixEvent` object: msgType, roomId, senderId, eventId, content, mediaUrl
- `gMxEvents` — module-level `Channel[MatrixEvent]`
- `pushEvent(payload)` — parses via matrix_pure.parseEvent; enqueues all supported kinds; ignores mxkUnknown
- `MatrixAdapter` with homeserver, botUserId, accessToken, apiBase, resolver, http
- `parseMxBody(resp)` — named `{.gcsafe, raises: [].}` proc for `>>=` chaining
- `extractEventId(j)` — named `{.gcsafe, raises: [].}` proc for `>>=` chaining
- `buildSendUrl(base, roomId, txnId)` — pure func building `/_matrix/client/v3/rooms/{roomId}/send/m.room.message/{txnId}`
- `buildSendBody(text)` — pure func building `{"msgtype":"m.text","body":"..."}` JSON body
- `sendChunk`, `sendToRoom`, `send`, `sendReturnId` — send procs using PUT + Bearer auth
- `editMessage` — sends m.replace replacement event for streaming edits
- `ack` — no-op (Application Service doesn't require explicit ack)
- `openQueue`, `startGateway`, `tryRecvEvent` — queue management with `{.cast(gcsafe).}`
- `nextTxnId()` — monotonic timestamp + global counter for unique Matrix transaction IDs
- `newMatrixAdapter` — constructor with optional apiBase override for testing
- Env vars: `MATRIX_HOMESERVER`, `MATRIX_BOT_USER_ID`, `MATRIX_ACCESS_TOKEN`

**Files changed:**
- `src/donkey/domain/channels/matrix_pure.nim` (new)
- `src/donkey/adapters/channel/matrix.nim` (new)
- `tests/channel/t_matrix.nim` (new)
- `src/donkey/core/types.nim` (updated: ckMatrix added)
- `src/donkey/ports/channel.nim` (updated: matrix* field added)
- `src/donkey/adapters/channel/outbound_builder.nim` (updated: matrix import + port + mxAdapter param)
- `src/donkey/app/outbound_runtime.nim` (updated: ckMatrix in all case statements)
- `src/donkey/donkey.nim` (updated: mx adapter field, import, init, buildOutboundPorts call)

**Learnings:**
- Matrix Client-Server API uses `PUT /_matrix/client/v3/rooms/{roomId}/send/m.room.message/{txnId}` for sending; response contains `event_id` (not `message_id`)
- Transaction IDs must be unique per request; using `nowMs() & counter` is sufficient for single-process adapters
- Matrix access tokens are long-lived (no expiry by default for bot accounts) — no token refresh logic needed
- Message editing uses `m.relates_to: {rel_type: "m.replace", event_id: ...}` with `m.new_content` block
- m.notice and m.emote are valid msgtypes that map to mxkText (same as m.text from the bot's perspective)
- Routing via room_id (not sender MXID) as rawId is the correct choice: the bot always replies to the room where the message came from, and `reverseChannel(userId, ckMatrix)` → room_id works naturally for outbound
- `outbound_runtime.nim` has case expressions inside template macros (`isOkOr`, `valueOr`) — when adding new enum values to combined `of X, Y, Z:` branches, they must stay on the same branch line (not separate `of ckMatrix: discard` on a new indented line outside the block)

---

## 2026-03-22 - US-028
- Implemented `src/donkey/adapters/channel/dingtalk.nim` — HTTP webhook adapter for DingTalk using dingtalk_pure
- Created `tests/channel/t_dingtalk.nim` with 26 tests covering identity, construction, event queue routing, and pure parser integration

**What was implemented:**
- `DingTalkEvent` object: msgType, rawId, messageId, content, downloadCode
- `gDtEvents` — module-level `Channel[DingTalkEvent]`
- `pushEvent(payload)` — parses via dingtalk_pure.parseEvent; enqueues dtkText/dtkImage/dtkAudio/dtkVideo/dtkFile; ignores dtkUnknown
- Group routing convention: rawId = "conv:" + conversationId for group events (isGroup=true)
- `DingTalkAdapter` with appKey, appSecret, robotCode, apiBase, resolver, http, accessToken, tokenExpirySec
- `parseDtBody(resp)` — named `{.gcsafe, raises: [].}` proc for `>>=` chaining
- `ensureAccessToken` — refreshes DingTalk token via `/v1.0/oauth2/accessToken`
- `buildSendUrl(apiBase, rawId)` — routes to `/v1.0/robot/groupMessages/send` (conv: prefix) or `/v1.0/robot/oToMessages/batchSend`
- `buildSendBody(robotCode, rawId, text)` — builds DingTalk robot message body with msgKey/msgParam pattern
- `sendToRawId`, `send`, `sendReturnId` — ChannelPort send procs; sendReturnId returns processQueryKey
- `editMessage` — no-op (DingTalk robot API doesn't support editing)
- `ack` — no-op (HTTP 200 suffices)
- `openQueue`, `startGateway`, `tryRecvEvent` — queue management with `{.cast(gcsafe).}` for global channel
- `newDingTalkAdapter` — constructor with optional apiBase override

**Files changed:**
- `src/donkey/adapters/channel/dingtalk.nim` (new)
- `tests/channel/t_dingtalk.nim` (new)

**Learnings:**
- DingTalk uses `x-acs-dingtalk-access-token` header (not `Authorization: Bearer`) for robot API calls
- Token endpoint is `/v1.0/oauth2/accessToken` with `{"appKey":..,"appSecret":..}`; response field is `accessToken` (camelCase, not `access_token`) and `expireIn` (not `expires_in`)
- Send body uses `msgKey: "sampleText"` and `msgParam: "{\"content\":\"..\"}"` (JSON-encoded string, not object)
- Group send uses `openConversationId` + `/v1.0/robot/groupMessages/send`; p2p uses `userIds: [rawId]` + `/v1.0/robot/oToMessages/batchSend`
- `{.cast(gcsafe).}` needed in both `pushEvent` (global Channel.send) and `tryRecvEvent` (global Channel.tryRecv) to suppress gcsafe warnings
- The `adapters/channels/` path in acceptance criteria is wrong — correct path is `adapters/channel/` (singular), consistent with all other channel adapters

---

## 2026-03-22 - US-026
- Implemented `src/donkey/adapters/channel/qq_webhook.nim` — HTTP webhook adapter for QQ official bot using qq_pure
- Created `tests/channel/t_qq_webhook.nim` with 22 tests covering identity, construction, event queue routing, and pure parser integration

**What was implemented:**
- `QQWebhookEvent` object: messageType, userId, groupId, messageId, content
- `gQQWbEvents` — module-level `Channel[QQWebhookEvent]` (same thread-safe pattern as other webhook adapters)
- `pushEvent(payload)` — parses via qq_pure.parseEvent; enqueues qqkPrivate, qqkGroup, qqkInteraction; ignores qqkUnknown
- `QQWebhookAdapter` with appId, clientSecret, apiBase, tokenBase, resolver, http, accessToken, tokenExpirySec
- `parseQqBody(resp)` — named `{.gcsafe, raises: [].}` proc for `>>=` chaining
- `ensureAccessToken` — refreshes QQBot bearer token via `{tokenBase}/app/getAppAccessToken`
- `buildSendUrl(apiBase, rawId)` — routes to /v2/users/{id}/messages or /v2/groups/{gid}/messages based on "group:" prefix
- `parseReplyToken(replyTo)` — splits "event:<id>" / "msg:<id>" into (kind, id)
- `buildSendBody(msg)` — builds QQ official bot message body with optional reply token
- `sendToRawId`, `send`, `sendReturnId` — ChannelPort send procs
- `editMessage` — no-op (QQ official v1 doesn't support editing)
- `ack` — no-op (HTTP 200 suffices)
- `openQueue`, `startGateway`, `tryRecvEvent` — queue management
- `newQQWebhookAdapter` — constructor with optional apiBase/tokenBase overrides

**Files changed:**
- `src/donkey/adapters/channel/qq_webhook.nim` (new)
- `tests/channel/t_qq_webhook.nim` (new)

**Learnings:**
- The acceptance criteria referenced "adapters/channels/qq.nim" (plural) but the existing codebase uses `adapters/channel/` (singular) and already has `qq.nim` (OneBot v11). The correct approach was to create `qq_webhook.nim` as the new QQ official webhook adapter using `qq_pure.nim`, parallel to `feishu.nim` using `feishu_pure.nim`.
- QQ official bot token uses `"QQBot " & token` header prefix (not "Bearer") — consistent with `qq_official.nim`
- `expires_in` can arrive as a JSON string (e.g. `"7200"`) or as an integer depending on QQ API version — handle both via kind check
- `sendReturnId` extracts `"id"` (not `"message_id"`) from QQ official bot send response — different from Feishu/Slack patterns
- The global channel pattern (`{.cast(gcsafe).}` in `openQueue`) is consistent across all webhook adapters; no change needed for this adapter

---

## 2026-03-22 - US-025
- Implemented `src/donkey/domain/channels/qq_pure.nim` — pure parser for QQ official bot event payloads
- Created `tests/domain/channels/t_qq_pure.nim` with 42 tests covering all event kinds

**What was implemented:**
- `QqMsgKind` enum: qqkPrivate, qqkGroup, qqkInteraction, qqkUnknown
- `QqParseResult` type with kind, rawId, groupId, messageId, text
- `getStr(name, node)` — field extractor for `|>->` piping (node as last arg)
- `parseC2cEvent(data)` — parses C2C_MESSAGE_CREATE (private DM)
- `parseGroupEvent(data)` — parses GROUP_AT_MESSAGE_CREATE / GROUP_MSG_RECEIVE
- `parseInteractionEvent(data)` — parses INTERACTION_CREATE; button data as "/callback <data>"
- `detectFlatEventType(data)` — infers event type from flat webhook payload (no "t" field)
- `parseDispatch(t, d)` — dispatches by event type string (gateway op=0 pattern, like discord_pure)
- `parseEvent(payload)` — top-level; handles wrapped gateway format (op+t+d) and flat webhook format
- `toInbound(r, userId)` — domain conversion; no mediaUrl (QQ official v1 has no media inbound)
- `qqRawIdentity(r)` — routing key: "group:<group_openid>" when groupId non-empty, else rawId
- `isInteraction(r)` — predicate; true for qqkInteraction
- `hasMedia(r)` — always false (no media support in current scope)

**Files changed:**
- `src/donkey/domain/channels/qq_pure.nim` (new)
- `tests/domain/channels/t_qq_pure.nim` (new)

**Learnings:**
- `qqRawIdentity` should check `groupId.len > 0` (not just `kind == qqkGroup`) — group interactions also carry a groupId and need the "group:" prefix for correct routing
- QQ official bot uses two payload formats: gateway dispatch `{"op":0,"t":"TYPE","d":{...}}` and flat webhook `{...fields directly...}` — the flat format is detected by checking for `group_openid` or `author.user_openid` presence
- `parseDispatch(t, d)` is the right API for QQ (same as discord_pure) because `t` and `d` arrive as separate fields — forcing a unary pipe would require wrapping; the adapter unwraps and calls `parseDispatch` directly
- The existing `qq_official.nim` already has many pure `func` helpers (`detectOfficialEventType`, `parseOfficialEventNode`, etc.) — `qq_pure.nim` provides a clean domain layer with a consistent `QqParseResult` type following the same pattern as other channel parsers

---

## 2026-03-22 - US-024
- Replaced `src/donkey/adapters/channel/feishu.nim` stub with a full HTTP webhook adapter
- Created `tests/channel/t_feishu.nim` with 20 tests covering identity, construction, challenge parsing, and event queue routing

**What was implemented:**
- `FeishuEvent` object: msgType, openId, msgId, chatId, chatType, content — backward-compatible with feishu_runtime.nim
- `gFsEvents` — module-level `Channel[FeishuEvent]` (same thread-safe pattern as Slack/WhatsApp)
- `parseChallenge(payload)` — wraps feishu_pure.parseEvent + isVerification; returns challenge string
- `pushEvent(payload)` — parses via feishu_pure and enqueues; ignores verification/unknown/fmkEvent/fmkInteractive
- `FeishuAdapter` with appId, appSecret, accessToken (tenant_access_token), apiBase, resolver, http
- `parseFsBody(resp)` — named `{.gcsafe, raises: [].}` proc validates HTTP status + Feishu "code" field
- `postJson(a, path, body)` — Feishu Open API helper using `>>=` chain
- `sendChunk` — sends text to open_id via `/open-apis/im/v1/messages?receive_id_type=open_id`
- `send`, `sendReturnId` — ChannelPort procs; sendReturnId chains `>>= extractMsgId`
- `editMessage` — PATCH `/open-apis/im/v1/messages/{msgId}` with updated content
- `ack` — no-op (HTTP 200 response suffices for Feishu webhook)
- `openQueue`, `tryRecvEvent` — queue management (non-var receiver, matches Slack/WhatsApp pattern)
- `startGateway` — wrapper around openQueue for compatibility with donkey.nim lifecycle
- `newFeishuAdapter` — constructor with accessToken and apiBase as optional params (backward-compatible)

**Files changed:**
- `src/donkey/adapters/channel/feishu.nim` (replaced stub with full webhook adapter)
- `tests/channel/t_feishu.nim` (new)

**Learnings:**
- The existing stub used `var FeishuAdapter` for `tryRecvEvent` — switching to non-var (matching Slack/WhatsApp) is safe because the module-level `Channel` is global and mutations don't go through the adapter instance
- `startGateway` must remain in the adapter even for webhook mode — `donkey.nim` calls it unconditionally in the lifecycle; for webhook adapters it simply calls `openQueue()`
- Feishu sends content as a JSON-encoded string inside the request body (e.g. `"content": "{\"text\":\"hello\"}"`) — the `sendChunk` proc must manually escape the message text for JSON embedding
- Feishu message editing uses `PATCH /open-apis/im/v1/messages/{id}` (not `PUT`) — use `http.patch`
- `StdHttpAdapter` already exports `patch` — no changes needed to the HTTP layer
- The `FeishuEvent` type kept backward-compatible field names (msgType, openId, msgId, content) so `feishu_runtime.nim` compiles without any changes

---

## 2026-03-22 - US-023
- Implemented `src/donkey/domain/channels/feishu_pure.nim` — pure parser for Feishu/Lark webhook event payloads
- Created `tests/domain/channels/t_feishu_pure.nim` with 32 tests covering all message kinds

**What was implemented:**
- `FsMsgKind` enum: fmkText, fmkImage, fmkAudio, fmkFile, fmkSticker, fmkInteractive, fmkEvent, fmkUnknown
- `FsParseResult` type with kind, rawId, messageId, text, fileKey, chatId, chatType, eventType, challenge
- `extractJsonStr(key, encoded)` — extracts string value from JSON-encoded string; designed for `|>->` (encoded string as last arg); avoids calling stdlib `parseJson` which is a `proc` (not `func`-compatible)
- `getField(name, node)` — string field extractor from JsonNode; designed for `|>->`
- `parseSenderId(sender)` — extracts open_id from nested sender_id object
- `parseMessage(event)` — inner dispatcher for im.message.receive_v1 events
- `parseEvent(payload)` — top-level parser; handles url_verification challenges, schema 2.0 message events, and other event types
- `toInbound(r, userId)` — domain conversion; fileKey goes to mediaUrl (adapter downloads via Feishu File API)
- `hasMedia(r)` — predicate; true for fmkImage, fmkAudio, fmkFile, fmkSticker
- `isVerification(r)` — predicate; true when url_verification challenge must be echoed back

**Files changed:**
- `src/donkey/domain/channels/feishu_pure.nim` (new)
- `tests/domain/channels/t_feishu_pure.nim` (new)

**Learnings:**
- `parseJson` from `std/json` is a `proc` (not `func`) in Nim 2.2 — cannot be called from a `func`; use string-based extraction for nested JSON strings instead
- Feishu `content` field is double-encoded JSON (a JSON string whose value is itself JSON) — the `extractJsonStr` helper scans for `"key":"value"` patterns covering common escapes
- Feishu url_verification payloads have a top-level `type` field (no `schema`/`header`) — must be detected before the schema 2.0 branch
- `ckFeishu` was already present in `core/types.nim` ChannelKind enum — no enum updates needed
- For audio/file/sticker, all three use `file_key` in content — a single `fmkAudio, fmkFile, fmkSticker` branch handles them identically

---

## 2026-03-22 - US-022
- `src/donkey/adapters/channel/wechat.nim` was already implemented (pre-existing)
- Verified: build passes (`nim check --mm:orc`), all 63 tests pass

**What was implemented (pre-existing):**
- `WeChatAdapter` with appId, appSecret, callbackToken, templateId, resolver, http
- `parseQueryString` — pure func; splits URL query string into Table
- `extractXmlTag` — extracts CDATA or plain tag content from XML
- `parseWebhookXml` — parses XML envelope into `WeChatEvent`; returns `Result[WeChatEvent, string]`
- `verifyWebhookSignature` — SHA1 verification of WeChat signature (sort+join+hash)
- `enqueueWebhookXml` — injects raw XML; pushes to thread-safe Channel or fallback seq
- `buildOAuthUrl` — OAuth2 URL builder
- `fetchAccessToken`, `fetchOAuthOpenId`, `fetchProfile` — WeChat API helpers
- `sendCustomText`, `sendTemplate` — sending via customer-service and template message APIs
- `wechatWebhookThread` / `startWebhook` — embedded HTTP/1.1 server on dedicated OS thread
- `tryRecvEvent`, `send` — ChannelPort-compatible procs

**Files changed:** none (already complete)

**Learnings:**
- WeChat webhook server uses `std/net` directly (not an HTTP framework) — same raw socket pattern as in Signal adapter
- `gWeChatEventsOpen` boolean guards whether to use the thread-safe channel or the direct injection queue; this allows test code to call `enqueueWebhookXml` without starting the server thread
- SHA1 signature: sort [token, timestamp, nonce] lexicographically, join, hash — `checksums/sha1` package handles this cleanly
- The adapter does NOT use `wechat_pure.nim` (US-021) — it duplicates `extractXmlTag` inline; this is pre-existing and consistent with its own `WeChatEvent` type rather than `WcParseResult`

---

## 2026-03-22 - US-021
- Implemented `src/donkey/domain/channels/wechat_pure.nim` — pure parser for WeChat/WeCom XML webhook payloads
- Created `tests/domain/channels/t_wechat_pure.nim` with 28 tests covering all message kinds

**What was implemented:**
- `WcMsgKind` enum: wckText, wckImage, wckVoice, wckVideo, wckFile, wckEvent, wckUnknown
- `WcParseResult` type with kind, rawId, msgId, text, mediaId, picUrl, eventType
- `extractTag(tag, xml)` — extracts CDATA-wrapped or plain tag content; designed for `|>->` (xml as last arg)
- `parseMsgKind(msgType)` — internal dispatcher for MsgType strings
- `parseXmlMsg(xml)` — top-level parser; `xml |> parseXmlMsg` returns WcParseResult
- `toInbound(r, userId)` — domain conversion; mediaId goes to mediaUrl (adapter resolves via Media API)
- `hasMedia(r)` — predicate; true for wckImage, wckVoice, wckVideo, wckFile
- `isEvent(r)` — predicate; true when kind is wckEvent

**Files changed:**
- `src/donkey/domain/channels/wechat_pure.nim` (new)
- `tests/domain/channels/t_wechat_pure.nim` (new)

**Learnings:**
- WeChat XML uses CDATA wrappers for string fields (`<![CDATA[…]]>`) but plain integers directly (MsgId, CreateTime) — `extractTag` handles both cases
- WeCom file messages have no CDATA quirks beyond the standard WeChat format; just adds `AgentID` and `FileName` fields
- Event messages have no MsgId in the XML — the msgId field is left empty; channelId in InboundMessage will be "" for events
- Test files using `|>->` need `donkey/core/pipeops` imported directly; not re-exported by the module under test
- Using `wck` prefix (WeChat Kind) avoids enum name collision with WhatsApp's `wmk` prefix in the same global namespace
- `shortvideo` maps to `wckVideo` (same treatment as `video`) — no separate kind needed

---

## 2026-03-22 - US-020
- Implemented `src/donkey/domain/channels/signal_pure.nim` — pure parser for signal-cli JSON-RPC receive envelopes
- Implemented `src/donkey/adapters/channel/signal.nim` — Signal adapter communicating via JSON-RPC over Unix socket
- Created `tests/domain/channels/t_signal_pure.nim` with 28 tests covering all envelope kinds
- Created `tests/channel/t_signal.nim` with 20 tests covering identity, construction, and event routing
- Added `ckSignal` to ChannelKind and updated all dependent files

**What was implemented:**
- `SigMsgKind` enum: smkText, smkAttachment, smkUnknown
- `SigParseResult` with kind, rawId, text, timestamp, attachmentId
- `parseEnvelope(item)` — parses a single result-array item from signal-cli receive
- `parseEnvelopes(items)` — filters result array, discards smkUnknown
- `toInbound(r, userId)` — domain conversion; attachmentId → mediaUrl field
- `hasAttachment(r)` — predicate; true for smkAttachment
- `firstAttachmentId(atts)` — extracts attachment id or filename from array
- `senderNumber(env)` — prefers sourceNumber, falls back to source
- `parseDataMessage(source, ts, data)` — designed for `|>->` (data as last arg)
- `rpcCall(sockPath, meth, params)` — standalone proc; opens Unix socket, sends JSON-RPC, reads response, closes
- `SignalAdapter` with sockPath, account, resolver
- `receive(var a)` — polls via JSON-RPC "receive", returns seq[InboundMessage]
- `send(a)` — sends via JSON-RPC "send" with E.164 recipient
- `sendReturnId(a)` — sends and returns timestamp as message id
- `editMessage(a)` — no-op (Signal doesn't support editing)
- `ack(a)` — no-op (daemon manages delivery receipts)
- `newSignalAdapter(account, identityPath, sockPath)` — constructor

**Files changed:**
- `src/donkey/domain/channels/signal_pure.nim` (new)
- `src/donkey/adapters/channel/signal.nim` (new)
- `tests/domain/channels/t_signal_pure.nim` (new)
- `tests/channel/t_signal.nim` (new)
- `src/donkey/core/types.nim` (added ckSignal)
- `src/donkey/ports/channel.nim` (added signal field to OutboundChannelPorts)
- `src/donkey/app/outbound_runtime.nim` (added ckSignal cases)
- `src/donkey/core/outbound/outbound.nim` (added ckSignal to isImplementedOutboundChannel set)

**Learnings:**
- Signal CLI communicates via JSON-RPC over Unix socket — no HTTP adapter needed; `std/net` directly handles the Unix domain socket
- `rpcCall` as a standalone proc (not a method) lets both `send` (immutable) and `receive` (var) call it without needing two proc variants
- signal-cli uses `sourceNumber` (always E.164) and `source` (may be UUID) — prefer `sourceNumber`, fall back to `source`
- Non-data envelopes (receipts, typing, sync, calls) have no `dataMessage` field — nil guard on `dataMessage` cleanly filters them to smkUnknown
- `editMessage` returns `ok()` but requires the unused parameters to be `discard`ed explicitly to suppress `--styleCheck:error` warnings
- Test files need `donkey/core/pipeops` imported to access `isOk` and other results helpers

---

## 2026-03-22 - US-019
- Implemented `src/donkey/adapters/channel/whatsapp.nim` — WhatsApp Cloud API webhook adapter
- Created `tests/channel/t_whatsapp.nim` with 20 tests covering identity, construction, verification, and event routing

**What was implemented:**
- `WaRawEventKind` enum: wrkText, wrkInteractive, wrkMedia
- `WaRawEvent` object with kind, waUserId, text, messageId, phoneNumberId, mediaId
- `gWaEvents` — module-level `Channel[WaRawEvent]` (same thread-safe pattern as Slack/Discord)
- `verifyChallenge(hubMode, hubChallenge, hubVerifyToken, configToken)` — returns challenge or "" for 403
- `pushEvent(payload)` — parses via whatsapp_pure and enqueues events; ignores wmkUnknown
- `openQueue()` / `tryRecvEvent()` — lifecycle and polling interface
- `postJson(path, body)` / `getJson(path)` — Graph API helpers using `>>=` chain
- `parseWaBody(resp)` — named `{.gcsafe, raises: [].}` proc validates HTTP status
- `resolveMediaUrl(mediaId)` — resolves WA media ID to download URL via Media API
- `sendChunk`, `send`, `sendToPhone`, `sendReturnId` — ChannelPort procs
- `extractMsgId(j)` — named `{.gcsafe, raises: [].}` proc for `>>= extractMsgId` chaining
- `ack(phoneNumberId, messageId)` — marks message as read via status update (errors silently ignored)
- `newWhatsAppAdapter(accessToken, phoneNumberId, identityPath, apiBase)` — constructor

**Files changed:**
- `src/donkey/adapters/channel/whatsapp.nim` (new)
- `tests/channel/t_whatsapp.nim` (new)

**Learnings:**
- WhatsApp webhook verification is a GET request (hub.mode/hub.challenge/hub.verify_token query params), not a JSON POST like Slack — `verifyChallenge` is a pure func taking four strings
- WA `ack` sends a POST with `{"status":"read","message_id":"..."}` to the messages endpoint, not a separate ACK endpoint
- Unlike Slack (DM channels) or Discord (dmChannels cache), WhatsApp sends directly to phone numbers — no channel ID resolution needed, simplifying `send` significantly
- `extractMsgId` as a named `{.gcsafe, raises: [].}` proc enables clean `>>= extractMsgId` in `sendReturnId` without a lambda wrapper
- `tables` import causes UnusedImport warning/error if no `Table` is used — remove it (WhatsApp adapter has no caching unlike Slack)

---

## 2026-03-22 - US-018
- Implemented `src/donkey/domain/channels/whatsapp_pure.nim` — pure (all `func`) parser for WhatsApp Cloud API webhook payloads
- Created `tests/domain/channels/t_whatsapp_pure.nim` with 34 tests covering all message kinds
- Added `ckWhatsApp` to `ChannelKind` enum and updated dependent files

**What was implemented:**
- `WaMsgKind` enum: wmkText, wmkInteractive, wmkMedia, wmkUnknown
- `WaParseResult` type with kind, rawId, text, messageId, phoneNumberId, mediaId
- `parseWebhook(payload)` — top-level dispatcher; walks entry→changes→value→messages array
- `parseMessage(phoneNumberId, msg)` — per-message dispatcher designed for `|>->`
- `parseTextMsg`, `parseInteractiveMsg`, `parseMediaMsg` — all designed for `|>->` (phoneNumberId as first arg, msg as last)
- `extractStr(name, node)` — field extractor for `|>->` piping
- `mediaIdFor(msgType, msg)` — extracts media id from dynamic sub-object keyed by type
- `toInbound(r, userId)` — domain conversion; mediaId goes to mediaUrl (adapter resolves to URL)
- `hasMedia(r)` — predicate; true for wmkMedia

**Files changed:**
- `src/donkey/domain/channels/whatsapp_pure.nim` (new)
- `tests/domain/channels/t_whatsapp_pure.nim` (new)
- `src/donkey/core/types.nim` (added ckWhatsApp)
- `src/donkey/ports/channel.nim` (added whatsapp field to OutboundChannelPorts)
- `src/donkey/app/outbound_runtime.nim` (added ckWhatsApp cases)
- `src/donkey/core/outbound/outbound.nim` (added ckWhatsApp to isImplementedOutboundChannel set)

**Learnings:**
- WA Cloud API nests messages three levels deep: entry[].changes[].value.messages[] — the helper `parseChangeValue` handles the innermost level cleanly
- `mediaIdFor(msgType, msg)` pattern: when the sub-object key equals the message type string (e.g. `msg["image"]["id"]`), passing the type string as an arg avoids a large case statement
- Status-only webhooks have a `statuses` array but no `messages` array — `getOrDefault("messages")` returning nil and the nil-guard returning `@[]` handles this without special-casing
- `toInbound` maps `mediaId` to `mediaUrl` field — the adapter must resolve the WA media ID to a URL via the Media API before the message is useful; this is consistent with Telegram's file_id → URL pattern

---

## 2026-03-22 - US-017
- Implemented `src/donkey/adapters/channel/slack.nim` — Slack Events API webhook adapter
- Created `tests/channel/t_slack.nim` with 20 tests covering identity, construction, challenge parsing, and event routing

**What was implemented:**
- `SlackRawEventKind` enum: srMessage, srSlashCommand, srBlockAction
- `SlackRawEvent` object with kind, slackUserId, text, channelId, teamId, responseUrl, triggerId
- `gSlackEvents` — module-level `Channel[SlackRawEvent]` (same thread-safe pattern as Discord)
- `parseChallenge(payload)` — returns challenge string for url_verification; empty otherwise
- `pushEvent(payload)` — parses via slack_pure and enqueues events; ignores verification/unknown
- `openQueue()` / `tryRecvEvent()` — lifecycle and polling interface
- `postJson(endpoint, body)` — Slack Web API helper using `>>=` chain (`http.post >>= parseSlackBody`)
- `parseSlackBody(resp)` — named `{.gcsafe, raises: [].}` proc validates HTTP status + Slack "ok" field
- `dmChannelFor(slackUserId)` — lazy DM channel resolution via `conversations.open` (cached in `ref Table`)
- `send()`, `sendToChannel()`, `sendReturnId()`, `editMessage()`, `ack()` — ChannelPort procs
- `newSlackAdapter(botToken, identityPath, apiBase)` — constructor

**Files changed:**
- `src/donkey/adapters/channel/slack.nim` (new)
- `tests/channel/t_slack.nim` (new)

**Learnings:**
- Disk full (100%) caused spurious compile failure — cleaned nimcache (209M) to free space
- The `ref Table` pattern for DM channel caching (same as Discord's `dmChannels`) works correctly with value receivers because mutations go through the ref
- `parseSlackBody` as a named `{.gcsafe, raises: [].}` proc enables clean `>>= parseSlackBody` chaining without lambda wrapping
- Slack webhook ack is implicit (HTTP 200 response from the HTTP layer) — `ack()` is a no-op
- `gSlackEvents.open()` must be wrapped in `{.cast(gcsafe).}` in `openQueue()` (same pattern as Discord)
- `export identity_resolver` in the adapter avoids double-import for downstream modules

---

## 2026-03-22 - US-016
- Implemented `src/donkey/domain/channels/slack_pure.nim` — pure (all `func`) parser for Slack Events API webhook payloads
- Created `tests/domain/channels/t_slack_pure.nim` with 40 tests covering all event kinds
- Added `ckSlack` to `ChannelKind` enum in `core/types.nim` and updated `outbound_runtime.nim`, `outbound.nim`, and `ports/channel.nim` accordingly

**What was implemented:**
- `SlkEventKind` enum: sekMessage, sekSlashCommand, sekBlockAction, sekVerification, sekUnknown
- `SlkParseResult` type with kind, rawId, text, channelId, teamId, eventTs, responseUrl, triggerId, challenge
- `parseEvent(payload)` — single dispatcher; routes by top-level `type` field
- `toInbound(r, userId)` — domain conversion to InboundMessage (uses `eventTs` as `channelId` for dedup)
- `isVerification(r)` — predicate; true when challenge ack is required
- Internal helpers: `extractField` (for `|>->` piping), `extractUserId` (handles both string and `{id}` object), `parseMessageEvent` (designed for `|>->` with teamId as first arg), `parseSlashCommand`, `parseBlockActions`

**Files changed:**
- `src/donkey/domain/channels/slack_pure.nim` (new)
- `tests/domain/channels/t_slack_pure.nim` (new)
- `src/donkey/core/types.nim` (added ckSlack)
- `src/donkey/ports/channel.nim` (added slack field to OutboundChannelPorts)
- `src/donkey/app/outbound_runtime.nim` (added ckSlack cases)
- `src/donkey/core/outbound/outbound.nim` (added ckSlack to isImplementedOutboundChannel)

**Learnings:**
- When a multi-arg helper needs to be used with `|>->`, make the piped subject the LAST parameter — `parseMessageEvent(teamId, event)` not `parseMessageEvent(event, teamId)`, then `event |>-> parseMessageEvent(teamId)` works correctly
- `|>` cannot be used with partial application like `event |> parseMessageEvent(teamId)` — that expands to `parseMessageEvent(teamId)(event)` which fails; use `|>->` instead when extra args are needed
- Adding a new `ChannelKind` enum variant requires updating several files: `core/types.nim` (`$`), `ports/channel.nim` (OutboundChannelPorts struct), `app/outbound_runtime.nim` (all case statements), `core/outbound/outbound.nim` (isImplementedOutboundChannel set)
- The `extractUserId` helper that handles both `"user": "U..."` (string) and `"user": {"id": "U..."}` (object) is needed because Slack uses different user formats in event callbacks vs block_actions payloads
---

## 2026-03-22 - US-015
- Refactored `src/donkey/adapters/channel/discord.nim` to use `discord_pure.parseDispatch` and pipeops operators
- Created `tests/channel/t_discord.nim` with 15 tests covering identity resolution, adapter construction, and dispatch routing

**What was implemented:**
- Added imports: `discord_pure` and `ports/http` (needed for `HttpResponse` in `>>=` helper procs)
- Replaced inline `handleDispatch` (150 lines) with a clean `case r.kind` dispatch using `parseDispatch(t, d)`
- Added `extractJsonId(j)` pure func for `|>` piping from JSON → id string
- Added `parseJsonBody(resp)` and `extractId(resp)` helper procs for `>>=` chaining
- Refactored `getAppId` to single-line: `a.http.get(...) >>= extractId`
- Refactored `sendReturnId` to use `>>= extractId` instead of manual parse
- Refactored `dmChannelFor` to use `parseJson(resp.body) |> extractJsonId`
- Fixed unused `DiscordGatewayUrl` constant by using it in `runGatewaySession` host extraction

**Files changed:**
- `src/donkey/adapters/channel/discord.nim` (refactored)
- `tests/channel/t_discord.nim` (new)

**Learnings:**
- `parseJsonBody >>= extractId` pattern is cleaner than inline try/except for JSON id extraction
- `DsEventKind` (discord_pure) maps to `DiscordEventKind` (adapter) via: dekMessage→deMessage, dekButtonClick→deButtonClick, dekModalSubmit→deInteraction, dekSlashCommand with needsModal→deModalRequest, dekSlashCommand with "/" content→deMessage, dekSlashCommand without "/"→deInteraction (/continue code)
- Unused module-level constants (e.g. `DiscordGatewayUrl`) generate a Hint (not warning), but it's cleaner to use them
- `extractId` as a named `{.gcsafe, raises: [].}` proc makes it directly usable in `>>=` without a lambda wrapper
---

## 2026-03-22 - US-014
- Implemented `src/donkey/domain/channels/discord_pure.nim` — pure (all `func`) parser for Discord gateway dispatch events
- Created `tests/domain/channels/t_discord_pure.nim` with 40 tests covering all event kinds

**What was implemented:**
- `DsEventKind` enum: dekMessage, dekSlashCommand, dekButtonClick, dekModalSubmit, dekUnknown
- `DsParseResult` type with kind, rawId, content, channelId, messageId, interactionId, interactionToken, needsModal
- `parseDispatch(t, d)` — single dispatch parser; routes by event type using `|>` for internal helpers
- `toInbound(r, userId)` — domain conversion to InboundMessage
- `hasInteraction(r)` — predicate; true when interaction ack is required
- Internal helpers: `extractDiscordUser`, `findOption` (designed for `|>->` piping), `buildSlashContent`, `parseMessageCreate`, `parseInteractionCreate`, `parseApplicationCommand`, `extractModalCode`

**Files changed:**
- `src/donkey/domain/channels/discord_pure.nim` (new)
- `tests/domain/channels/t_discord_pure.nim` (new)

**Learnings:**
- `findOption` was designed as `findOption(name, opts)` so `opts |>-> findOption(name)` works (piped value last)
- Guild context interactions carry `member.user` instead of top-level `user` — extractDiscordUser handles both
- Discord op=0 dispatches arrive as `(t, d)` pairs, not a single node; `parseDispatch(t, d)` is the natural API rather than forcing a unary pipe
- `|>` still useful internally: `d |> parseMessageCreate`, `d |> extractDiscordUser`, `d |> extractModalCode`
---

## 2026-03-22 - US-012
- Implemented `src/donkey/domain/channels/telegram_pure.nim` — pure (all `func`) parser for Telegram Bot API updates
- Created `tests/domain/channels/t_telegram_pure.nim` with 25 tests covering all update kinds

**What was implemented:**
- `TgParseResult` type with kind, rawId, sessionKey, text, channelId, callbackId, hasMedia, mediaFileId
- `parseUpdate(JsonNode): TgParseResult` — single update parser using `|>` pipeline
- `parseUpdates(JsonNode): seq[TgParseResult]` — batch parser filtering unknowns
- `toInbound(r, userId, mediaUrl): InboundMessage` — domain conversion
- `maxNextOffset(currentOffset, updates): int64` — offset calc for polling; designed for `|>->`
- `hasCallbackId(r): bool` — predicate for ack-required updates

**Files changed:**
- `src/donkey/domain/channels/telegram_pure.nim` (new)
- `tests/domain/channels/t_telegram_pure.nim` (new)

**Learnings:**
- `|>->` macro puts the piped value as the LAST argument — functions designed for it must have the "subject" as last param (opposite of UFCS)
- `func` works fine with `JsonNode` in Nim — no side effects despite GC types
- `warningAsError` is on globally via `config.nims`; unused imports cause build failure
- Test files need explicit `import donkey/core/pipeops` to use `|>` — not re-exported by the module under test
---

## 2026-03-22 - US-013
- Refactored `src/donkey/adapters/channel/telegram.nim` to use `telegram_pure.nim` and pipeops operators

**What was implemented:**
- Added `import ../../domain/channels/telegram_pure` and `import ../../ports/http`
- Extracted `parseTgResp(meth, resp)` as a named `{.gcsafe, raises: [].}` helper
- Refactored `post` to use `>>=`: `http.post(...) >>= proc(resp): ... = parseTgResp(meth, resp)`
- Refactored `getFileUrl` to use `>>=`: `post("getFile", ...) >>= proc(resp): ok(base & ... & path)`
- Refactored `receive` to use pure parser: `updates |> parseUpdates`, `r.toInbound(userId, mediaUrl)`, `updates |>-> maxNextOffset(a.offset)`
- Removed redundant `extractMediaUrl` proc (replaced by `r.hasMedia` / `r.mediaFileId` from pure parser)

**Files changed:**
- `src/donkey/adapters/channel/telegram.nim` (refactored)

**Learnings:**
- `>>=` with inline closures that capture outer locals: define a named `{.gcsafe, raises: [].}` proc and delegate to it — the inline closure becomes a trivial one-liner that is provably gcsafe
- `HttpResponse` is NOT re-exported by `std_http` — must import `ports/http` directly when referencing it in signatures
- The pure parser (`telegram_pure`) cleanly replaces the manual for-loop in `receive`; adapter only handles side-effectful work (ack, file URL resolution, identity)
---

## 2026-03-22 - US-027
- Implemented pure DingTalk Stream mode parser

**What was implemented:**
- Added `ckDingTalk` to `ChannelKind` enum in `src/donkey/core/types.nim` with `"dingtalk"` string representation
- Created `src/donkey/domain/channels/dingtalk_pure.nim` — pure parser for DingTalk Stream SDK payloads
- Created `tests/domain/channels/t_dingtalk_pure.nim` — 20 tests covering all message types and edge cases
- Updated `src/donkey/ports/channel.nim` — added `dingtalk*` field to `OutboundChannelPorts`
- Updated `src/donkey/app/outbound_runtime.nim` — added `ckDingTalk` to all case branches
- Updated `src/donkey/core/outbound/outbound.nim` — added `ckDingTalk` to `isImplementedOutboundChannel`

**Files changed:**
- `src/donkey/core/types.nim`
- `src/donkey/domain/channels/dingtalk_pure.nim` (new)
- `tests/domain/channels/t_dingtalk_pure.nim` (new)
- `src/donkey/ports/channel.nim`
- `src/donkey/app/outbound_runtime.nim`
- `src/donkey/core/outbound/outbound.nim`

**Learnings:**
- DingTalk Stream SDK payload: text in `text.content` for text/markdown types; media in JSON-encoded `content` field with `downloadCode` key for picture/audio/video/file
- The `extractJsonStr` pattern (pure string scanner for JSON-encoded string fields) is reusable across multiple channel parsers — each module implements its own copy to stay self-contained (no cross-channel imports)
- Adding a new `ChannelKind` requires updating: `types.nim` (enum + `$`), `ports/channel.nim` (OutboundChannelPorts field), `outbound_runtime.nim` (3 case branches), `outbound.nim` (set literal in `isImplementedOutboundChannel`)
---
