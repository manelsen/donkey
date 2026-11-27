# Interfaces
Agent-facing HTTP API and the operator dashboard.

## Overview

The embedded HTTP gateway exposes two surfaces on the same port:

- **`/v1/chat/completions`** — an OpenAI-shaped endpoint that runs the *real*
  agent turn (session, memory, tools) and answers once, either as a single
  `chat.completion` or as an SSE stream of `chat.completion.chunk` events.
- **Dashboard** — a public HTML shell plus three Bearer-protected endpoints for
  reading sessions, reading provider health and starting one new conversation.

Both are served by `app/http_gateway.nim`; the agent turn lives in
`app/agent_chat_runtime.nim`, the correlation in `app/chat_bridge.nim`, and the
wire formats in `domain/gateway/`.

| Endpoint | Method | Auth | Purpose |
|---|---|---|---|
| `/v1/chat/completions` | POST | Bearer + token configured | Run one agent turn |
| `/v1/models` | GET | Bearer | The configured model, `owned_by: donkey` |
| `/v1/acp/pair` | POST | none | An editor asks to pair (E10.2) |
| `/v1/acp/pair/poll` | POST | the pairing secret | The editor collects its credential once confirmed |
| `/v1/acp/chat/completions` | POST | Bearer: the editor's credential | One streamed turn as the paired person |
| `/v1/acp/approve` | POST | Bearer: the editor's credential | The person's answer to an approval asked in the editor |
| `/v1/acp/editor_result` | POST | Bearer: the editor's credential | The editor's answer to a request the daemon sent (a file read) |
| `/api/sessions` | GET | Bearer | Paged session list |
| `/api/providers` | GET | Bearer | Provider health table |
| `/api/sessions/{userId}/task` | POST | Bearer | `{"action":"new"}` |
| `/dashboard` | GET | public | HTML shell, no data |
| `/`, `/health` | GET | public | Plain-text liveness |

`DONKEY_HTTP_PORT` defaults to `8080`; `0` disables the gateway.
`DONKEY_HTTP_BIND` defaults to `127.0.0.1`; a non-loopback bind requires
`DONKEY_HTTP_TOKEN` **and** `DONKEY_HTTP_ALLOW_INSECURE=1`, because the gateway
speaks cleartext HTTP.

---

## Authentication and identity

`DONKEY_HTTP_TOKEN` is the only credential. Every non-public route requires
`Authorization: Bearer <token>`; the comparison is constant-time and the token
is instance-wide. `OPTIONS` is answered with `204` before the check so browser
preflights work.

The agent endpoint additionally refuses to run **without** a configured token:

- token missing (`DONKEY_HTTP_TOKEN` unset/empty) → `503`
  `{"error":{"message":"agent endpoint requires DONKEY_HTTP_TOKEN",...}}`.

This is deliberate. `/v1/*` keeps its historical local-only gate behind that
check, but a route that runs the full agent loop is not exposed
unauthenticated even on loopback.

The dashboard data routes (`/api/*`, including `/api/sessions`,
`/api/providers` and the session action) also require the Bearer token even
when the client comes from loopback and even for `OPTIONS`: there is no
unauthenticated mode for them, so a gateway started without
`DONKEY_HTTP_TOKEN` answers `401` there. `/`, `/health` and the `/dashboard`
shell stay public; the shell asks for the token once and keeps it in
`sessionStorage`.

The request field `user` is the identity. It must match `[a-z0-9._-]{1,64}`,
must not be `.` or `..`, and is turned into the synthetic user id
`UserId("api:" & user)` (`domain/gateway/identity_pure.nim`). Consequences:

- Uppercase, slashes, spaces and names longer than 64 characters are a `400`.
- `alice` and a channel user `alice` are different identities (`api:alice`
  versus `alice`); the prefix is what keeps the namespaces apart.
- `user` is **caller-asserted**. The Bearer token authenticates the client
  against the instance, not the user inside the body. Any token holder can act
  as any `api:` identity. Per-user credentials are an explicit non-goal:
  `tests/app/t_http_gateway.nim` pins this so the limitation stays a decision
  rather than a bug.

A turn for an `api:` user never enters channel onboarding: the orchestrator
skips the onboarding state machine for `isApiUserId(...)` users, so the API
reaches the normal agent turn with whatever profile/memory already exists.
Onboarding is skipped, so no profile is created for it.

---

## Editors (E10.2)

An editor (Zed and others, through `donkey acp`) speaks **as a person**, not
as an `api:` user: same identity, same session, same memory as on their
channels. It pairs the device-flow way, so nothing reachable from the
network can be guessed:

1. The editor calls `POST /v1/acp/pair` with `{"name":"Zed"}` and gets
   `{"code","pairing","expiresIn","confirmWith"}`. It shows the six-character
   code and keeps `pairing`, a long secret.
2. The person sends `/editor <code>` on a channel where Donkey already knows
   them. Codes live ten minutes; at most 32 wait at once.
3. The editor polls `POST /v1/acp/pair/poll` with `{"pairing"}`: `202` while
   pending, then `200 {"token"}` once, then `404`.
4. Turns go to `POST /v1/acp/chat/completions` with `Authorization: Bearer
   <token>` and the body of `/v1/chat/completions` (`stream: true`; the `user`
   field is ignored). The answer is the same SSE stream.

The daemon keeps only the token's SHA-256 in `state/editors.json` (0600),
with the person, the editor's name and a public id. The person lists and
revokes their editors with `/editor` and `/editor revogar <id>` (at most 16 per
person); the operator
with `donkey ctl editor list|revoke`. A revocation takes effect on the next
request. A person who is revoked or not allowed by the DM policy is refused
here too. These routes never take `DONKEY_HTTP_TOKEN`: an editor holds only
its own credential. An editor's turn does not change the channel the
person's reminders go to.

**Approvals (E10.4).** A tool that asks for approval during an editor's turn
asks in the stream: a chunk whose delta is `donkey_approval` (`text`, and
`options` with each button's `label` and `callback`; an OpenAI client
ignores it). The editor answers with `POST /v1/acp/approve`, `{"callback":
"approval:<id>:allow|deny|always"}` and its credential, decided by the same
handler as a channel's button, as the paired person; anything that is not an
approval's callback is a 400. A token-less message of an editor's turn still
goes to the channel the person last wrote from.

**Reading in the editor (E10.5).** The `editor_read_file` tool (approval by
default) works only in an editor's turn: it sends a `donkey_editor_request`
chunk (`id`, `method: "fs/read_text_file"`, `params`), and waits up to 60 s
for `POST /v1/acp/editor_result` (`{"id","content"}` or `{"id","error"}`),
which only the person whose turn asked can answer, once. Content is cut at
200 KiB.

## `POST /v1/chat/completions`

### Request

The endpoint runs the same path as a CLI/channel message: `dispatch` →
`handleGatewayFallback` → session ingress/actor → memory + tools → outbox. The
only things the client chooses are the user and the current text.

| Field | Behavior |
|---|---|
| `user` | Required, string, non-empty; validated as above |
| `messages` | Required, non-empty array; roles must be `user`/`assistant` |
| `model` | Optional, echoed when no instance model is configured; never routes |
| `stream` | Optional boolean; any other type is `400` |
| `tools` | `[]` accepted; any non-empty array is `400 unsupported_parameter` |
| `tool_choice`, `response_format` | Presence (non-null) is `400` |
| `n` | `1` and `null` accepted; `0`, negatives, `> 1` and non-numeric types are `400 unsupported_parameter` |
| `system`/`developer` messages | `400 unsupported_parameter` |
| `temperature`, `top_p`, `max_tokens` | Ignored, not validated |

The last message must be `user`, and its content may be a string or an array of
`{"type":"text"}` parts (non-text parts are ignored, not rejected). Only that
last message's text is sent; earlier history is validated for roles but its
content is discarded — the session owns conversation history. The dispatched
message is:

```nim
InboundMessage(
  userId:    UserId("api:" & user),
  channel:   ckCli,
  channelId: "api:" & user,
  text:      <last user message>,
)
```

Every turn is keyed per `api:<user>`: session, history and paddock are per user.

Outbox replies for that user are diverted by `drainGlobalOutbox`: `isApiChatReply`
is true for any message whose `userId` starts with `api:`, so the reply goes to
the `ChatBridge` and never to a channel port. `replyKind` decides what may become
client-visible content:

| Reply kind | Meaning on this endpoint |
|---|---|
| `rkFinalAnswer` (`isPartial=false`) | The one answer; closes the turn |
| `rkFinalAnswer` (`isPartial=true`) | Content delta for SSE; ignored by JSON path |
| `rkToolNotice` | `tool_calls` delta in SSE; never content |
| `rkTurnError` | Terminal error (redacted); `502` or SSE error event |
| `rkDebug`, `rkChannel` | Dropped |

### Non-streaming response

With `stream` absent or `false`, the handler writes exactly one
`chat.completion` after the terminal event:

```json
{
  "id": "chatcmpl-1763500000",
  "object": "chat.completion",
  "created": 1763500000,
  "model": "donkey/default",
  "choices": [{
    "index": 0,
    "message": {"role": "assistant", "content": "Olá!"},
    "finish_reason": "stop"
  }],
  "usage": {"prompt_tokens": 123, "completion_tokens": 45, "total_tokens": 168}
}
```

`content` is the terminal `rkFinalAnswer` text and nothing else: partials are
never concatenated, and tool notices/progress/debug lines never leak into it.
`finish_reason` is `"stop"`, or `"length"` when the terminal answer exceeded the
bridge buffer (256 KiB) and was clipped. `model` is the instance's
`default_model`; if that is empty, the request's `model` is echoed, and if both
are empty the literal is `donkey/default`. `id` is derived from the Unix time at
response time (`chatcmpl-<seconds>`), so two turns in the same second share it.

The HTTP handler does not send headers until the turn finishes, so a
non-streaming call is silent for its whole duration.

---

## Streaming (`stream: true`)

A well-formed body with `stream: true` takes the SSE path; parse errors stay on
the JSON path so they can be answered with a status before any byte is written.
Validation, authorization, the per-user reservation and the SSE slot are all
acquired **before** the response headers.

Headers:

```http
HTTP/1.1 200 OK
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
```

There is no `event:` field, only `data:`.

Chunk sequence:

1. One role chunk, with no `content`:
   `{"id":"chatcmpl-…","object":"chat.completion.chunk","created":…,"model":"…","choices":[{"index":0,"delta":{"role":"assistant"}}]}`
2. Zero or more `content` deltas: one per streamed partial of `rkFinalAnswer`,
   plus at most one for the unseen suffix of the terminal answer.
3. Zero or more `tool_calls` deltas for named tool notices.
4. One finish chunk: `delta` is `{}`, `finish_reason` is present, and `usage` is
   present at the root.
5. `data: [DONE]` and close.

`role` appears only in the first chunk and `finish_reason`/`usage` only in the
last. Absent keys are omitted, not sent as `null`.

A tool chunk:

```json
{"id":"chatcmpl-…","object":"chat.completion.chunk","created":…,"model":"…",
 "choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"type":"function",
 "id":"call_1","function":{"name":"web_search"}}]}}]}
```

This is the whole tool-call contract: `index` is always `0`, `function.name` and
(optionally) `id` are present, `arguments` is never emitted, the notice `phase`
is not transmitted, and no chunk carries `finish_reason: "tool_calls"`. Tool
notices whose `name` and `id` are both empty (the `✅ N tool call(s)` summary)
are not sent at all. A strict OpenAI client that accumulates tool calls will see
names without arguments and should treat them as progress, not as a call it can
execute.

### Append-only content

The stream never takes content back. When the terminal `rkFinalAnswer` arrives:

- if the streamed text is a prefix of the terminal text, only the unseen suffix
  is sent as one more delta;
- if it is not a prefix, the terminal text is **dropped** and the stream finishes
  with whatever already went out. The finish chunk still reports the terminal's
  usage and `finish_reason: "stop"`.

So the concatenated `delta.content` always equals what the client received, but
it may be shorter than the daemon's final answer. There is no signal for that
case other than the content itself.

### `finish_reason: "length"`

Two triggers, both ending with a normal finish chunk and `[DONE]`:

- the terminal answer is larger than the bridge buffer `MaxTurnBufferBytes`
  (256 KiB) and was clipped — the non-streaming path reports the same `length`;
- the stream reached `MaxSseChunksPerTurn` (4096 data chunks). The cap is checked
  before writing a content or tool chunk; the finish chunk is still written.

When the chunk cap fires before the terminal was seen, the reported `usage` is
`0/0/0`, because no terminal event carried tokens. Keepalive comments and
`[DONE]` do not count towards the 4096.

### Keepalive

While the turn is still open, a comment line `: ping` (blank line terminated) is
sent at most once per `SseKeepaliveIntervalMs` (15 s) of the gateway's clock. It
carries no data and is not a chunk. Sends are bounded by the socket timeout; a
failed send (including a timeout) means the client is gone.

### Failure after the first byte

Once the headers are out, the status is already `200`. The only failure shape is
one redacted error event followed by a close — **no** finish chunk and **no**
`[DONE]`:

```text
data: {"error":{"message":"…","type":"provider_error","code":"turn_error"}}
```

| Cause | `type` / `code` |
|---|---|
| Terminal `rkTurnError` | `provider_error` / `turn_error` |
| Deadline | `timeout_error` / `turn_timeout` |
| Entry no longer pending | `server_error` / `turn_missing` |

Messages pass through `redactForClient`: `Bearer` and `Basic` credentials,
`sk-` keys, the Slack/GitHub/AWS/Google prefixes (`xoxb-`, `ghp_`, `AKIA…`,
`AIza…`), and the `key`/`token` shapes — including the JSON form with a colon —
become `[redacted]`. The text is capped at 300 bytes. Over-redaction is
preferred to a leak; prose such as `monkey: business` is left alone because the
colon form requires a quoted value.

This differs from the PRD, which asked for the error event **plus** `[DONE]`; the
code (and its tests) deliberately close without `[DONE]` so a client cannot
mistake a failed turn for a completed one.

If the client leaves (`send` returns false), the runtime calls
`bridge.abandon`: waiting stops, but the turn is **not** cancelled. The key stays
reserved until the orphan's terminal arrives or `MaxOrphanTtlMs` (600 s) expires,
so a late answer can never become the next turn's content. A new turn for the
same user gets `429` until then.

### Preflight failures

Before the first byte every failure is a plain JSON response with a real status
(`400`, `401`, `403`, `413`, `429`, `502`, `503`). That includes the SSE slot
check (`429` `rate_limit_error` / `sse_capacity`) and the per-user reservation
(`429` / `chat_bridge_busy`).

---

## Status mapping

Runtime errors use the OpenAI shape
`{"error":{"message":…,"type":…,"code":…}}`. Socket-level errors (auth, method,
unknown route, connection/stream caps) use `{"error":"…"}` plain text/JSON.

| Status | When | Body |
|---|---|---|
| `200` | Turn completed | `chat.completion` or the SSE stream |
| `202` | Dashboard action queued | `{"status":"accepted"}` |
| `204` | CORS preflight | empty |
| `400` | Body does not parse as a valid turn (`invalid_request`, `unsupported_parameter`, `missing_required_parameter`) or a bad action body | OpenAI-shaped or `{"error":"…"}` |
| `401` | Missing/wrong Bearer on a non-public route | `{"error":"unauthorized"}` |
| `403` | `authorize` returned `avRevoked`/`avNotAllowed` — **before dispatch** | `{"error":{"message":"permission_error","type":"permission_error"}}` |
| `403` | Cross-origin request while no token is configured | `{"error":"cross-origin access requires a token"}` |
| `404` | Unknown route, unknown session key | plain text or JSON |
| `405` | Wrong method for a known path | empty body |
| `413` | Body/`Content-Length` over `MaxApiRequestBytes` (1 MiB) | `invalid_request_error` / `payload_too_large` |
| `429` | A turn is already pending for this `api:` user | `rate_limit_error` / `chat_bridge_busy` |
| `429` | SSE slot/budget exhausted | `rate_limit_error` / `sse_capacity` |
| `429` | Turn queue full (`MaxPendingTurns`) | `rate_limit_error` / `too_many_pending_turns` |
| `429` | Long-lived worker budget full | `rate_limit_error` / `no_worker` |
| `502` | Terminal `rkTurnError` (provider failure) | `provider_error` / `turn_error`, redacted |
| `502` | `dispatch` threw before a turn started | `server_error` / `dispatch_failed` |
| `503` | `DONKEY_HTTP_TOKEN` not configured | `server_error` |
| `503` | Runtime or dashboard hook not wired | `server_error` / `{"error":"…"}` |
| `504` | No terminal before the deadline | `timeout_error` / `turn_timeout` |

Authorization order matters: the ingress refusal runs in `prepareTurn` **before**
`dispatch`, so the refusal text is never produced as agent content and no session
state is touched.

Outside the agent endpoint, the accept loop and queue caps answer `503` with
plain text ("too many connections"), and `/api/events` answers `503 "too many
event streams"` when the shared SSE/long-lived admission refuses it.

The POST is authorized entirely at preflight in the streaming path. A provider
error that arrives after the first byte is therefore a `200` plus an SSE error
event, never a `502`.

Non-streaming `cbpMissing` (the pending entry disappeared) maps to `504`
`turn_timeout` even though the cause is not strictly a timeout; the streaming
path reports it as `turn_missing`.

---

## Concurrency and limits

### One turn per user

`ChatBridge.register` refuses a second pending turn for the same
`$userId` (`api:<name>`): `429`, code `chat_bridge_busy`. The reservation is
released when the terminal event is polled, when `abandon` + orphan terminal/TTL
closes it, or after the deadline (entry marked orphaned, key retained). A turn
can be in flight from only one HTTP request at a time, per user.

### Worker budget

The gateway has `GatewayWorkerCount = 8` workers, a queue of 64 and at most 32
live connections. Long-lived work is bounded to `MaxLongLivedWorkers = 6`, leaving
2 workers for `/health`, `/dashboard`, `/api/status`, `/api/logs`, `/v1/models`
and 503 responses. `MaxConcurrentSseConnections = 4` covers `/api/events` **and**
streaming chat, which share the same counter and the same 6-worker ceiling.

Both paths are admitted by the same policy. A non-streaming turn reserves
`llChatTurn` through `tryReserveLongLived` before the agent is dispatched and
releases it in `finally` (including dispatch failure, deadline and a client
abort, before the response is written), and a stream reserves
`llSseConnection` the same way. The counter is incremented only on `cvAdmit`, so
a refused request never consumes or releases a worker.

`MaxPendingTurns = 4` is therefore enforced, and 4 pending + 4 SSE is refused
for both classes, because the sum is checked against the 6-worker ceiling even
when a worker is free. `cvTooManyPendingTurns` answers 429
`too_many_pending_turns`; `cvNoWorker` answers 429 `no_worker` (a saturated
budget is transient backlog; 503 stays reserved for missing wiring).

### Deadline

`DONKEY_HTTP_AGENT_TIMEOUT_SEC`:

| Value | Effective turn deadline |
|---|---|
| unset / invalid / `0` / negative | 120 s |
| `1`…`600` | that many seconds |
| `> 600` | 600 s |

The deadline is fixed at registration (`register(userId, timeoutMs)`) and drives
`bridge.poll`. On expiry the runtime answers `504` (JSON) or sends a
`turn_timeout` error event (SSE) and marks the entry orphaned; it does not cancel
the agent turn. Separately, `GatewayRequestDeadlineSec = 15` bounds reading the
request line, headers and body — it is not the agent deadline.

### Disconnects

Neither path cancels the turn. Non-streaming: the turn runs to completion and the
write fails silently. Streaming: `abandon` stops waiting and keeps the key
reserved as described above.

---

## Usage

`usage` is reported in `prompt_tokens` / `completion_tokens` / `total_tokens`,
mapped from the terminal event's `inputTokens`/`outputTokens`
(`buildAgentChatResponse`, `buildAgentChunk`). `total_tokens` is the sum.

- The daemon accumulates `UsageTotals` with `addUsage` once per provider round,
  including streamed rounds, in `core/tooling/tool_loop.nim`. A turn with two
  tool rounds reports the sum of all three rounds.
- Partials and tool notices carry no tokens; the finish chunk is the only SSE
  carrier. Nothing is counted twice.
- Negative provider values are clamped with `max(0, …)` in `addUsage` and again on
  the streamed terminal, so totals never decrease.
- When the answer comes from the round-1 streaming path (no tool calls), the
  terminal is emitted by `streamToOutbox` and carries that single round's clamped
  usage — the same total, since only one round ran.
- No terminal means no usage: a `504` / error event has no usage object.

---

## Dashboard

`GET /dashboard` returns a public, data-free HTML shell. The page asks for the
Bearer token in a password field, keeps it in `sessionStorage`, and sends
`Authorization: Bearer <token>` on every fetch. Without a token it sends no
header (which only works when the instance has no token configured).
`setInterval(refresh, 5000)` re-reads status, logs, sessions and providers.
Rows are built with `textContent`, never `innerHTML`, so session/user data cannot
become markup.

CSP:

```text
default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'
```

`default-src 'none'` stays the base; the two `'unsafe-inline'` directives are what
allow the page's own style/script block, and `connect-src 'self'` allows its
fetches. No token and no data are embedded in the HTML.

### `GET /api/sessions`

Query: `limit` (default 50, max 200, `<= 0` → 50), `offset` (`< 0` → 0, past the
end → clamped to the row count). Invalid query values fall back instead of
failing, so a bad query is never a `500`. Non-GET is `405`; a missing hook is
`503`.

```json
{"sessions":[{"sessionId":"…","userId":"…","channels":["telegram"],
  "lastInboundAt":"2026-11-18T12:00:00Z","live":true}],
 "limit":50,"offset":0,"total":1}
```

`lastInboundAt` is UTC ISO-8601, or `""` when unknown. `live` is the inverse of
the manager's `restored` flag.

### `GET /api/providers`

One entry per `providerDescriptor`, canonical ids only:

```json
[{"id":"openrouter","available":true,"cooldownUntil":"","calls":12,"ok":11,
  "err":1,"avgLatencyMs":840,"health":"degraded"}]
```

`health` is `missing` (not available), then `cooling` (active cooldown), then
`degraded` (`calls > 0` and `err > 0`), else `ok`. `cooldownUntil` is ISO-8601 or
`""`. Non-GET is `405`; a missing hook is `503`.

### `POST /api/sessions/{userId}/task`

Body: exactly `{"action":"new"}`. Anything else — empty body, invalid JSON, a
non-object, `{"kind":"reset"}`, `{"action":"reset"}` — is `400` with a fixed
message. The action is the same `tkNew` control task used by `/new`
(`ensureSessionTask(..., tkNew, "")`), i.e. archive the current session and start
a fresh one. It is queued, hence `202 {"status":"accepted"}`; the confirmation
("Nova conversa iniciada. 👋") is a normal outbox reply on that user's channel,
not part of the HTTP response.

The path id is the **raw session key**, not an API identity: it is never passed
through `apiUserId`. `%`, `/`, `?`, `#`, `.` and `..` are refused by the path
parser, which makes such a path fall through to the generic `404` (plain text),
not a `400`.

Order of checks: `401` (socket, before the body is read) → `503` if the hook is
unwired → `400` for the body → the hook's outcome: `202`, `404` (raw key not in
`sm.entries`), or `403` (`isRevoked`). A malformed body beats both `404` and
`403` because it is parsed first; the hook is never called in that case.

The hook looks the key up in the live session table and refuses to create a
session: only an existing key can be restarted.

---

## Examples

Non-streaming:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Authorization: Bearer $DONKEY_HTTP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "user": "alice",
    "messages": [{"role": "user", "content": "oi"}]
  }'
```

Streaming (`-N` disables curl buffering):

```bash
curl -sN http://127.0.0.1:8080/v1/chat/completions \
  -H "Authorization: Bearer $DONKEY_HTTP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "user": "alice",
    "stream": true,
    "messages": [{"role": "user", "content": "resuma o que sabemos"}]
  }'
```

```text
data: {"id":"chatcmpl-1763500000","object":"chat.completion.chunk",…,"choices":[{"index":0,"delta":{"role":"assistant"}}]}

data: {…,"choices":[{"index":0,"delta":{"content":"Temos"}}]}

data: {…,"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":123,"completion_tokens":45,"total_tokens":168}}

data: [DONE]
```

The second call with the same `user` reuses the same session, so context and
memory carry over even though the request only carries the new message.

Dashboard action:

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://127.0.0.1:8080/api/sessions/00000000-0000-0000-0000-000000000000/task \
  -H "Authorization: Bearer $DONKEY_HTTP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"new"}'
```

---

## Limits and non-goals

- **No per-user authentication.** One instance token; `user` is claimed, not
  proven. There is no per-token user mapping and no OAuth. A leaked token is
  full access to every `api:` identity and to the dashboard action.
- **No rate limit per token or IP**, no turn queue, no fairness. The only throttle
  is one in-flight turn per `api:` user plus the worker/SSE ceilings.
- **No cancellation.** A disconnect abandons the wait, not the turn; the key
  stays reserved for the orphan TTL.
- **No `tools`/`tool_choice` from the client**, no `system` override, no
  `response_format`, no `n > 1`. The tool catalog and prompt belong to the agent.
- **No tool-call execution contract.** SSE exposes names as informational
  `tool_calls` deltas; there are no arguments, and `finish_reason` never becomes
  `tool_calls`.
- **One answer per turn.** Exactly one `chat.completion`, or one content stream
  that ends with one finish chunk; tool notices and debug text are never content.
- **Out of scope:** `responses`, Anthropic/Gemini shapes, embeddings, audio,
  images, provider/skill/config management over HTTP (that stays in
  `donkey ctl`), and a complete web UI.
- **No persistence of API turns as a separate record.** The session owns the
  transcript; there is no request ledger.

## Known divergences from the PRD

Documented from the code, not smoothed over:

1. **`[DONE]` after a mid-stream error.** the interfaces PRD (US-003; in git history since `tasks/` was removed) asks
   for `{"error":…}` **plus** `[DONE]`. The runtime sends the error event and
   closes without a finish chunk and without `[DONE]`; the test asserts exactly
   that. A failed stream is therefore not terminated like a success.
2. **`cvNoWorker` status.** The PRD does not pin a status for a saturated
   worker budget; the gateway answers 429 for both capacity verdicts and keeps
   503 for missing wiring.
3. **Tool notice `phase`.** The PRD lists `phase: "start"|"done"`; the runtime
   only emits `"done"` (the summary notice has no name/id and is not streamed).
4. **`tools: []`.** The PRD says client `tools` are refused; an *empty* array is
   accepted and ignored, and only a non-empty array is `400`.
5. **Dashboard `400 {"kind":"reset"}`.** Both `{"kind":"reset"}` and
   `{"action":"reset"}` are `400`, but the body is `{"error":"missing action"}`
   or `{"error":"unknown action: reset"}`, not an echo of the request.

`docs/reference/configuration.md` is also stale: it still describes
`/v1/chat/completions` as a provider proxy where "tools and streaming are
rejected", and its curl example omits the now-required `user` field.

## Related

- [Configuration](../reference/configuration.md)
- [Sessions](sessions.md)
- [Providers](providers.md)
- [Architecture](../architecture.md)
