# Channels
Messaging platform integrations

## Overview

Donkey exposes a unified channel abstraction over the messaging adapters it ships.
The adapters translate between platform-specific APIs and Donkey's internal
message format, while outbound UI behavior is governed by the shared capability
model in `core/outbound`.

## Supported Channels

This matrix reflects the current `core/outbound` capability model used by the runtime.

| Channel | Implemented | Editable UI | Stream updates | Components | Reactions |
|---------|-------------|-------------|----------------|------------|-----------|
| [Telegram](#telegram) | yes | yes | yes | yes | yes |
| [Discord](#discord) | yes | yes | yes | yes | yes |
| [Slack](#slack) | yes | no | no | no | no |
| [LINE](#line) | yes | no | no | no | no |
| [Microsoft Teams](#microsoft-teams) | yes | no | no | no | no |
| [Mattermost](#mattermost) | yes | no | no | no | no |
| [SMS (Twilio)](#sms-twilio) | yes | no | no | no | no |
| [IRC](#irc) | yes | no | no | no | no |
| [Google Chat](#google-chat) | yes | no | no | no | no |
| WeChat Work | yes | no | no | no | no |
| WeChat | yes | no | no | no | no |
| QQ | yes | no | no | no | no |
| Feishu | yes | no | no | no | no |
| WhatsApp | yes | no | no | no | no |
| Signal | yes | no | no | no | no |
| DingTalk | yes | no | no | no | no |
| Matrix | no | no | no | no | no |
| Email | no | no | no | no | no |
| CLI | no | no | no | no | no |

---

## Telegram

### Features
- Text messages
- Inline keyboards
- Message editing
- Reactions
- Media (photos, documents)
- Voice messages

### Configuration

```bash
export TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN
```

### Bot Commands

Register commands with BotFather:
```
/start - Start conversation
/menu - Show menu
/help - Show help
```

### Inline Keyboards

```nim
let buttons = @[
  @[("Yes", "yes"), ("No", "no")],
  @[("Cancel", "cancel")]
]
adapter.sendKeyboard(userId, "Continue?", buttons)
```

---

## Discord

### Features
- Text messages
- Embeds
- Components (buttons, select menus)
- Slash commands
- Reactions
- DM-oriented editable UI surfaces

### Configuration

```bash
export DISCORD_BOT_TOKEN=YOUR_DISCORD_TOKEN
```

### Required Intents

Enable these in Discord Developer Portal:
- `MESSAGE CONTENT INTENT` - Required for reading messages
- direct messages / message create events for DM use

### Slash Commands

Register in your server or globally via API.

---

## Slack

### Features
- Messages
- Basic outbound send/edit support via adapter

### Configuration

```bash
# Slack support is adapter-level today and not part of the recommended
# quickstart path. Configure the corresponding adapter tokens in the env
# used to start Donkey.
```

### Required Scopes

- `chat:write`
- `commands`
- `app_mentions:read`

---

## LINE

### Features
- Text messages (push and single-use reply)
- Group and multi-user room conversations
- Webhook-driven inbound (no polling, no long-lived connection)
- Send only: no edits, keyboards, reactions, media, or voice notes

### Configuration

```bash
export LINE_CHANNEL_ACCESS_TOKEN=YOUR_CHANNEL_ACCESS_TOKEN
export LINE_CHANNEL_SECRET=YOUR_CHANNEL_SECRET
export LINE_ALLOWED_GROUPS=C0123456789abcdef,Cfedcba9876543210
export LINE_ALLOWED_USERS=U0123456789abcdef
```

| Variable | Required | Meaning |
|----------|----------|---------|
| `LINE_CHANNEL_ACCESS_TOKEN` | yes | Bearer token for push/reply. It also gates the channel: without it the LINE route is not mounted and the webhook queue is not opened. |
| `LINE_CHANNEL_SECRET` | yes | HMAC key for `X-Line-Signature`. With an empty secret `/webhook/line` answers 404. |
| `LINE_ALLOWED_GROUPS` | no | Comma-separated `groupId`/`roomId` values, exact match. **Empty or unset = no group or room is allowed.** |
| `LINE_ALLOWED_USERS` | no | Comma-separated `source.userId` values, exact match, applied to DMs and groups. Empty or unset = every speaker allowed. |

`LINE_API_BASE` optionally overrides the API host (HTTPS required outside
loopback; the default is `https://api.line.me`). Entries in the two allowlists
are trimmed and deduplicated; an empty entry is dropped.

### Webhook

Point the Messaging API channel at the public HTTPS endpoint:

```
https://your-public-host/webhook/line
```

1. Set the channel's **Webhook URL** to that endpoint.
2. Press **Verify** in the console. It posts `{"events":[]}`, which is answered
   `200 ok` without enqueueing an event.
3. Enable **Use webhook** and **Webhook redelivery**. The route answers `503`
   when its bounded queue is full, and LINE only retries when redelivery is on;
   the retries are best-effort, so a sustained backlog can still lose an event.

The receiver itself is enabled by `DONKEY_WEBHOOK_PORT` and binds
`DONKEY_WEBHOOK_HOST` (default `127.0.0.1`). It also accepts plain HTTP, so
public HTTPS normally comes from a TLS-terminating proxy or from
`DONKEY_WEBHOOK_TLS_CERT`/`DONKEY_WEBHOOK_TLS_KEY`.

One receiver serves every callback channel. WeCom, WeChat and QQ OneBot
used to run their own listeners (`WECOM_WEBHOOK_PORT`, `WECHAT_WEBHOOK_PORT`,
`QQ_ONEBOT_WEBHOOK_PORT`/`_HOST`); those variables are no longer read, and
startup warns when one is still set. Register these callback URLs instead:

| Channel | Path | Mounted when |
|---|---|---|
| WeCom | `/webhook/wecom` | `WECOM_CORP_ID` and `WECOM_CALLBACK_TOKEN` are set; `msg_signature` is required |
| WeChat | `/webhook/wechat` | `WECHAT_APP_ID` and `WECHAT_CALLBACK_TOKEN` are set |
| QQ OneBot | `/webhook/qq` | the OneBot backend is configured; with `QQ_ONEBOT_SECRET` every POST needs `X-Signature`, without it the route is mounted only when the receiver binds to loopback |

Redelivery can stay enabled: repeated `webhookEventId` values are dropped for
24 hours (see below). `deliveryContext.isRedelivery` is read for telemetry only
and never drives a decision.

### Signature

`X-Line-Signature` carries `base64(HMAC-SHA256(channel_secret, raw_body))`,
computed over the request body exactly as received. There is no signed
timestamp; replay defence is the `webhookEventId` cache, not an ingress time
window.

Because the MAC covers raw bytes, re-serialising the JSON, pretty-printing it,
or changing any whitespace produces a 403. A proxy in front of the receiver must
not rewrite the body.

| Condition | Response |
|-----------|----------|
| Secret not configured | `404` (the route looks absent) |
| Method other than `POST` | `405` |
| Body larger than 1 MiB | `413` |
| Missing or wrong signature | `403` |
| Malformed or empty JSON body | `400` |
| Accepted (including `{"events":[]}`) | `200 ok` |

Checks run in that order, so an unconfigured route answers 404 even for a `GET`,
and a request with a bad signature never reaches the JSON parser.

Two edges sit at the HTTP boundary rather than in the LINE route: a declared
`Content-Length` above the receiver's global 2 MiB read cap is rejected before
routing with `413`, and the LINE route itself answers `413` above 1 MiB; a
saturated worker queue (4 workers, 32 pending connections) answers `503`.

### Behaviour

- **Text only.** Inbound, only `message` events whose `message.type` is `text`
  are answered. Stickers, images, files and non-message events (follow,
  postback, …) are consumed and dropped. Outbound, `send` refuses media
  (`LINE: media unsupported (text only)`) and keyboards
  (`LINE: keyboards unsupported (text only)`) explicitly instead of dropping
  them silently, and `downloadFile` always fails with
  `LINE: media unsupported`.
- **Standby is dropped.** Events with `mode: "standby"` are consumed without a
  reply, because another module owns the answer.
- **Groups must be allowlisted.** A `source.type == "group"` event is gated by
  its `groupId` and a `room` event by its `roomId`; both are matched exactly
  against `LINE_ALLOWED_GROUPS`, and an empty list denies every group and room.
  Groups and rooms share one list — there is no separate room allowlist.
- **DMs are open by default.** A `source.type == "user"` event is allowed
  unless `LINE_ALLOWED_USERS` is non-empty; when set, the list applies to every
  speaker, in DMs and groups alike, and matching is exact (`U1` does not admit
  `U10`).
- **Duplicate event ids are dropped for 24 hours.** `webhookEventId` is kept in
  an in-memory cache with a 24 h TTL and at most 1,000 ids (the oldest is
  evicted). An event without an id is never treated as a duplicate. The cache
  is not persisted, so a daemon restart forgets recently seen ids.
- **Identity is the speaker; the reply target is the conversation.**
  `source.userId` becomes the Donkey identity while `chatId` — the
  `groupId`/`roomId`, or the `userId` in a DM — becomes the conversation. A
  group therefore answers in the group, and two speakers in the same group keep
  distinct identities. Outbound precedence is `OutboundMessage.replyTo`, then
  the last conversation that speaker wrote from (remembered in memory by the
  adapter), then the speaker's raw id (a DM). A proactive send with neither
  `replyTo` nor a remembered conversation goes to the speaker's DM, not to the
  group.

Accepted events then go through the shared identity/pairing authorization. That
gate is called with `isGroup = false` even for a group event, so the LINE
allowlist is the only group-level gate and the speaker is authorized like a DM
identity. The LINE gates run first, so a denied event never creates a session,
identity, or pairing request.

### Limits

- **One push per send.** `send` issues a single
  `POST /v2/bot/message/push`; the whole text is split into bubbles in that
  same call, so a long answer cannot be delivered partially or duplicated by a
  retry.
- **4,500 characters per bubble.** Chunks are measured in Unicode characters,
  not bytes; the API's hard per-bubble cap is 5,000, so 4,500 leaves headroom.
  Breaks prefer a paragraph, then a line, then a word boundary.
- **At most 5 bubbles.** A sixth chunk is not sent: the last bubble is
  truncated to fit and ends with `…`.
- **No retries and no reply→push fallback.** A failed push or reply is returned
  as an error. Reply tokens are single-use, and a refused reply is never retried
  as a push. The adapter exposes `sendReply`, but the inbound runtime answers
  with pushes, so the parsed `replyToken` is currently unused.
- **429 handling.** A 429 records a channel-wide flood window (`Retry-After`
  seconds, or the `retry_after`/`retryAfter` body field, default 5 s). Sends
  attempted while the window is active fail immediately without calling the
  API.
- **Startup order.** The webhook queue is opened once at daemon startup,
  before the receiver binds, because HTTP workers enqueue into it. The queue,
  the flood window, and the dedupe cache all live in memory.

### Disabling

Unset `LINE_CHANNEL_ACCESS_TOKEN`: the channel is treated as absent, the queue
is not opened, the drain is a no-op, and `/webhook/line` answers 404. Unsetting
only `LINE_CHANNEL_SECRET` also makes that route answer 404 while the receiver
keeps serving other channels.

---

## Microsoft Teams

Teams reaches Donkey through the Bot Framework: an Azure Bot resource whose
messaging endpoint is `https://<your host>/webhook/teams` on the shared
webhook receiver. Bots created since July 2025 are single-tenant.

### Configuration

| Variable | Required | Meaning |
|---|---|---|
| `MICROSOFT_APP_ID` | yes | The bot's App ID: the audience every incoming token must carry. |
| `MICROSOFT_APP_PASSWORD` | yes | The app's client secret, for the token Donkey sends with. Without both, `/webhook/teams` answers 404. |
| `MICROSOFT_APP_TENANT_ID` | single-tenant | The tenant the app is registered in; its token endpoint is used. Empty = the old multi-tenant endpoint. |
| `TEAMS_SERVICE_HOSTS` | no | Connector hosts besides `smba.trafficmanager.net` that replies may go to (comma-separated, exact). |

### What is checked

Every POST must carry a JWT from the Bot Connector, checked as in Microsoft's
"Authenticate requests with the Bot Connector API": RS256 signature with a key
from `login.botframework.com` (fetched at first use, renewed daily, and again
when a token names an unknown key, at most every five minutes), issuer
`https://api.botframework.com`, audience the App ID, validity with five
minutes of skew, the `serviceurl` claim equal to the activity's, and the key's
endorsement of the channel. A failure is a 401 (403 for the endorsement) and
nothing is queued.

### Behaviour

- Personal chats follow the DM policy; group chats and channels pass the
  shared group allowlist (`DONKEY_TELEGRAM_ALLOWED_GROUPS`, with the
  conversation id before `;messageid=`; empty = every group).
- In a channel the bot's own `@mention` is taken out of the text.
- A person is known by their Entra object id, so `/continue` links Teams to
  the same person on another channel.
- Replies are Markdown in the thread of the message they answer; long ones
  go in pieces. Each person's last conversation is kept in
  `state/teams_conversations.json`, so reminders reach them after a restart.
- Text only: no attachments, cards or edits yet.

---

## Mattermost

Mattermost reaches Donkey over its WebSocket API: no public URL is needed.
Create a bot account (System Console → Integrations → Bot Accounts), give it a
personal access token, and add it to the teams and channels it should serve.

### Configuration

| Variable | Required | Meaning |
|---|---|---|
| `MATTERMOST_URL` | yes | The server, `https://` only (the socket and every request carry the token). |
| `MATTERMOST_TOKEN` | yes | The bot's personal access token. |

### Behaviour

- At connection Donkey asks `users/me` who the bot is, then authenticates the
  socket with the token. A token the server refuses stops the connection
  (reconnecting cannot help); other drops reconnect with backoff, and a ping
  every 30 s keeps the link alive.
- Direct messages follow the DM policy. In a channel the bot answers only when
  mentioned, and the channel passes the shared group allowlist
  (`DONKEY_TELEGRAM_ALLOWED_GROUPS`, with the channel id; empty = every
  group). The `@mention` is taken out of the text.
- A person is known by their Mattermost user id, so `/continue` links
  Mattermost to the same person on another channel.
- Replies in a channel go into the thread of the post they answer; direct
  messages get a plain post. Long replies go in pieces. Each person's last
  direct channel is kept in `state/mattermost_channels.json`, so reminders
  reach them after a restart.
- Posts made while the socket is down are not replayed.
- Text only: no attachments or edits yet.

---

## SMS (Twilio)

SMS goes through a Twilio phone number. In the console, set the number's
"A message comes in" webhook to `https://<your host>/webhook/sms` (HTTP POST)
on the shared webhook receiver.

### Configuration

| Variable | Required | Meaning |
|---|---|---|
| `TWILIO_ACCOUNT_SID` | yes | The account the number belongs to. |
| `TWILIO_AUTH_TOKEN` | yes | Signs the webhooks and authenticates the replies. |
| `TWILIO_FROM_NUMBER` | yes | The Twilio number replies come from (E.164, e.g. `+5511…`). |
| `TWILIO_WEBHOOK_URL` | yes | The webhook URL exactly as set in the console: the signature covers it. Without it (or the token) `/webhook/sms` answers 404. |

### Behaviour

- Every POST must carry a valid `X-Twilio-Signature` (HMAC-SHA1 of the URL
  and the sorted parameters with the auth token); anything else is a 403 and
  nothing is queued. The webhook answers an empty TwiML: the reply goes
  through the Messages API.
- A person is their phone number; messages follow the DM policy, and
  `/continue` links the number to the same person on another channel.
- A message Twilio redelivers is a turn once.
- Text only: a message with media and no text gets a short answer; long
  replies go in several messages (1600 characters each).

---

## IRC

Donkey keeps one connection to an IRC network, over TLS only (the SASL
password and every message cross it).

### Configuration

| Variable | Required | Meaning |
|---|---|---|
| `IRC_SERVER` | yes | `host` or `host:port` (6697 by default). |
| `IRC_NICK` | yes | The bot's nick; `_` is appended while it is taken. |
| `IRC_PASSWORD` | no | The bot's services password, for SASL PLAIN login as `IRC_NICK`. |
| `IRC_CHANNELS` | no | Channels to join (comma-separated). |
| `IRC_REALNAME` | no | The real name shown by WHOIS (`Donkey`). |

### Behaviour

- A nick proves nothing on IRC, so a person is their **services account**:
  the network must offer the IRCv3 `account-tag` capability, and only
  messages it vouches for (users logged in to NickServ or equivalent) are
  answered. Without it the bot connects and logs why, but answers nobody.
- Private messages follow the DM policy. In a channel the bot answers only
  when addressed by name (`donkey: …` or `donkey, …`), and the channel passes
  the shared group allowlist (`DONKEY_TELEGRAM_ALLOWED_GROUPS`, with the
  channel name; empty = every group).
- `/continue` links the account to the same person on another channel; each
  account's last nick is kept in `state/irc_nicks.json`, so reminders reach
  them after a restart.
- Replies are one `PRIVMSG` per line, cut under 400 bytes, paced (a burst of
  5, then one line every 600 ms) so the network does not kick the bot.
- The connection answers `PING`, pings a silent server after 2 minutes,
  reconnects after 4 minutes of silence or any drop, with backoff.
- Text only; CTCP and notices are ignored.

---

## Google Chat

Google Chat reaches Donkey as a Chat app with an HTTP endpoint. In the Google
Cloud console (Google Chat API → Configuration), set the connection to
**HTTP endpoint URL** `https://<your host>/webhook/google-chat` and the
**authentication audience** to **Project number**. Create a service account
for the app and a JSON key for it.

### Configuration

| Variable | Required | Meaning |
|---|---|---|
| `GOOGLE_CHAT_PROJECT_NUMBER` | yes | The Cloud project number: the audience every incoming token must carry. Without it `/webhook/google-chat` answers 404. |
| `GOOGLE_CHAT_SERVICE_ACCOUNT` | yes | The service account key's JSON. Keep it in the vault: `donkey ctl secret set GOOGLE_CHAT_SERVICE_ACCOUNT`. |

### What is checked

Every POST must carry a bearer token Google signed: RS256 with one of the keys
Chat publishes (fetched at first use, renewed daily, and again when a token
names an unknown key, at most every five minutes), issuer
`chat@system.gserviceaccount.com`, audience the project number, within five
minutes of skew. Anything else is a 401 and nothing is queued.

### Behaviour

- Only messages from people are turns. Direct messages follow the DM policy;
  in a space Chat only sends the app messages that mention it, and the space
  passes the shared group allowlist (`DONKEY_TELEGRAM_ALLOWED_GROUPS`, with
  the space name, `spaces/…`; empty = every group). The mention is taken out.
- A message Chat delivers again is a turn once.
- A person is their Chat user (`users/…`), so `/continue` links them to the
  same person on another channel. Each person's direct space is kept in
  `state/google_chat_spaces.json`, so reminders reach them after a restart.
- The webhook answers at once; replies go through the Chat API as the
  service account (its own RS256 assertion, exchanged for a `chat.bot` token
  renewed before it expires), in the thread of the message they answer, in
  pieces under 4000 characters.
- Text only: no cards, attachments or edits yet.

---

## Several bots per channel

One instance can run several bots on a channel, each with its own token and
persona, over the same users, memory and sessions (a person is one user on
every bot). Declared in `donkey.toml`:

```toml
[[bots]]
name      = "suporte"
channel   = "telegram"
token_env = "TELEGRAM_TOKEN_SUPORTE"
agent     = "suporte"      # {home}/agents/suporte.toml
```

- The bot answers with its agent's persona and model (an agent file in the
  instance's `agents/`, the same format as a person's named agents); a
  message that starts with `@agent` still picks that agent.
- The bot a person wrote to last is the one that answers them, on every path
  of that channel (replies, streaming edits, keyboards, typing); reminders
  go through it too, and through the default bot after a restart until the
  person writes again.
- An entry that is malformed or whose token variable is not set is left out
  and logged at startup; the others run.
- On Discord each bot keeps its own gateway connection. Direct messages
  sent while the daemon was down are recovered only for the default bot:
  the recovery cursor is one per person and each bot has its own DM
  channels.
- On WhatsApp a bot is another number of the same Meta account
  (`phone_number_id = "…"` instead of `token_env`): the numbers share the
  account's token and webhook, and the number a message was sent to picks
  the bot. A number this instance does not serve is still ignored.
- On Teams a bot is another Azure Bot (`app_id = "…"` and
  `secret_env = "…"`, the variable with its password) on the same
  `/webhook/teams` route: the audience of the connector's token says which
  bot an activity is for. The bots use the tenant of the default one
  (`MICROSOFT_APP_TENANT_ID`), and each keeps its conversations in
  `state/teams_conversations_<bot>.json`.
- Available on Telegram, Discord, WhatsApp and Teams.

---

## CLI

The CLI is not part of the outbound capability matrix. It is an operational
surface for `setup`, `doctor`, `about`, `service`, and local daemon control.

### Usage

```bash
./donkey about
./donkey doctor
./donkey service start
```

### Example Session

```
Snapshot
--------
- storage: SQLite-first MAGMA (/home/user/.donkey/state/magma.sqlite)
- default model: smart routing
- web search: disabled (set BRAVE_API_KEY to enable web_search)
- sandbox: mode=oci, runtime=docker, network=off, rootfs=ro, host-fallback=off
```

---

## Channel Selection

When a message is received, the channel is automatically detected:

```nim
case inbound.channel
of ckTelegram:
  echo "From Telegram"
of ckDiscord:
  echo "From Discord"
of ckSlack:
  echo "From Slack"
of ckCli:
  echo "From CLI"
```

---

## Multi-Channel Sessions

A user can be reached across multiple channels:

```
User: alice
├── telegram
├── discord
└── qq
```

The runtime keeps channel identity mappings while the session/memory layer owns
the actual conversational state.

---

## DM Policy

Control who can send direct messages:

See `docs/reference/configuration.md` for the active DM policy fields and the
current config shape.

---

## Message Format

### Inbound

```nim
InboundMessage* = object
  userId*:    UserId       # Platform user ID
  channelId*: string      # Platform message ID
  text*:      string      # Message content
  mediaUrl*:  string      # Attached media URL
  channel*:   ChannelKind # Source channel
```

### Outbound

```nim
OutboundMessage* = object
  userId*:    UserId      # Target user
  text*:      string      # Message text
  replyTo*:   string      # Message ID to reply to
  channel*:   ChannelKind # Target channel
  keyboard*:  seq[seq[(string, string)]]  # Buttons
  mediaUrl*:  string      # Media URL
```

---

## Related

- [Configuration Reference](../reference/configuration.md)
- [Channel Port API](../reference/channel_port.md)
