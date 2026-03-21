# QQ Official API Notes

Local reference pages saved from `https://bot.q.qq.com/wiki/`:

- `send.html`
- `api-use.html`
- `event-emit.html`
- `websocket.html`
- `message-event.html`
- `markdown.html`
- `msg-btn.html`
- `rich-media.html`
- `unique-id.html`

Key constraints confirmed from the official docs:

- Access token flow:
  - `POST https://bots.qq.com/app/getAppAccessToken`
  - request body: `appId`, `clientSecret`
  - response: `access_token`, `expires_in`
- OpenAPI auth:
  - base URL: `https://api.sgroup.qq.com`
  - header: `Authorization: QQBot <access_token>`
- C2C send:
  - `POST /v2/users/{openid}/messages`
- Group send:
  - `POST /v2/groups/{group_openid}/messages`
- Rich send fields:
  - `msg_type`
  - `content`
  - `markdown`
  - `keyboard`
  - `ark`
  - `embed`
  - `media`
  - `event_id`
  - `msg_id`
  - `msg_seq`
- Important inbound event types:
  - `C2C_MESSAGE_CREATE`
  - `GROUP_AT_MESSAGE_CREATE`
  - `GROUP_MSG_RECEIVE`
  - `INTERACTION_CREATE`
- Important intents from `event-emit.html`:
  - `GROUP_AND_C2C_EVENT (1 << 25)`
  - `INTERACTION_CREATE`

Current repo status on branch `feat/qq-official-api`:

- `qq_official.nim` implements:
  - access token acquisition
  - official message send for C2C and groups
  - official event normalization for C2C and group messages
- `qq_channel.nim` is the compatibility seam:
  - wraps either OneBot or official QQ
  - keeps `ckQQ` unchanged
  - exposes normalized inbound events to the runtime

Still pending:

- official QQ ingress loop from webhook/WebSocket to `enqueueEventJson()`
- keyboard/markdown rendering against the official `msg-btn` schema
- interaction callbacks (`INTERACTION_CREATE`)
