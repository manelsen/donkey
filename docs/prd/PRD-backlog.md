# PRD-backlog: what the V5 coverage left partial

Status: draft, 24/11/2026. Source: the coverage report's §11.3 ("what went in
partial") and §11.5 ("priorities"), `~/git/COBERTURA_HERMES_VS_DONKEY_V5.md`.
Since then, automation (#146–#148), observability (#149) and conversation
search and recall (#150–#164) were done and are not in this PRD.

## Goal

Close the partial items that need no product decision, each as its own PR,
tested on Donkey's real paths, and update the coverage report at the end.

## Items, in order

| # | Item | Why now | Size |
|---|---|---|---|
| 1 | Streaming through the selected provider | two partials share one cause | L |
| 2 | Tools for agents that are consulted | multiagent's main gap | M |
| 3 | MCP OAuth with a pre-registered client | a refused case today | S |
| 4 | Alibaba `preserve_thinking` | quality between turns, small | S |
| 5 | Channel depth: WhatsApp | the Discord and Slack method, still unapplied there | M |
| 6 | Azure OpenAI as a provider | breadth without OAuth | M |
| 7 | Coverage report §12 | records the measured changes | S |

### 1. Streaming through the selected provider

Today only the default provider streams (`StreamFactory` is OpenRouter's).
Two partials come from that:
- **Bedrock:** it has no streaming.
- **Named agents:** an agent with its own model answers in one piece.

**Scope:**
- Streaming becomes a property of the selected route. A provider that can
  stream offers a `nimcall` stream builder, as OpenRouter's does. The tool
  loop picks the builder for the route it is about to call, and a route
  without one answers in one piece, as today.
- **Bedrock ConverseStream.** AWS's event-stream framing (prelude, headers,
  payload, two CRC32 checksums) is decoded in a pure module, tested against
  bytes recorded from the documented format. A frame that fails its
  checksum ends the stream as an error, never as text.
- **Named agents with their own provider** stream through the same path.

**Acceptance:**
- A Bedrock route and a named agent with its own model both stream partial
  edits to a channel.
- The decoder refuses a corrupt frame.
- The OpenRouter streaming tests still pass.

### 2. Tools for agents that are consulted

`ask_agent` and `convene_agents` answer in one reply, without tools, so a
consulted specialist cannot look anything up.

**Scope:**
- A consulted agent gets a bounded tool loop with a read-only set of tools:
  - `session_search`;
  - `current_time`;
  - `calc`;
  - `web_search` and `fetch` only where the user's web policy allows them.
- It never gets `ask_agent`, `convene_agents`, `manage_*`, `bash`, file
  writes or schedules: the same hard denials as subagents
  (`SubagentHardDeniedTools`).
- **Bounds:** at most 4 tool rounds per answer, a wall-clock deadline per
  agent, and a room's agents still run in parallel.

**Acceptance:**
- An agent asked a question about the past answers from `session_search`.
- An agent cannot call another agent.
- A room with three agents and tools finishes inside its deadline.

### 3. MCP OAuth with a pre-registered client

An authorization server without dynamic registration is refused today.

**Scope:** `donkey ctl mcp login <url> --client-id ID [--client-secret-env NAME]`.
- A public client uses PKCE as today.
- A confidential client authenticates at the token endpoint
  (`client_secret_basic`, or `client_secret_post` when the server's
  metadata asks for it).
- The secret is read from the environment snapshot, never stored in the
  token file.

**Acceptance:**
- Login and refresh work against a fake server without a registration
  endpoint, for both client kinds.
- The token file holds no secret.

### 4. Alibaba `preserve_thinking`

Qwen 3.6+ on DashScope keeps its reasoning across turns only when the
request asks for it, and Donkey does not ask.

**Scope:** a quirk in the Alibaba profile that sends the parameter for the
models documented to accept it, plus the reasoning content echoed back
where the API requires it (as DeepSeek's quirk does).

**Acceptance:** the request shape for those models matches DashScope's
documentation, checked first, and other models are unchanged.

### 5. Channel depth: WhatsApp

Discord and Slack were hardened by mining Hermes's fixes
(`docs/hermes-mining`). WhatsApp was never compared that way; Matrix may
follow later.

**Scope:**
- Mine Hermes's WhatsApp history into the traceability file (cases WA-…).
- Classify each case: fixed in Donkey, applicable, or not applicable.
- Fix the applicable ones, test-first, one PR per group.

**Acceptance:** every mined case has a status and evidence in
`TRACEABILITY.md`.

### 6. Azure OpenAI as a provider

**Scope:**
- **Endpoint:** a deployment URL with `api-version`, and an `api-key`
  header.
- **Wire format:** the OpenAI one, through the compat path with a profile
  for its quirks.
- **Configuration:** the endpoint, deployment and key from the environment
  snapshot.

Vertex AI is not here: its service-account login needs RS256 signing, which
the project does not have. See the questions below.

**Acceptance:** a completion and a tool round against a recorded Azure
response, and the provider listed in `ctl` and doctor.

### 7. Coverage report §12

Re-score the domains with the method of §11 (only what runs counts),
covering automation, observability, memory and the items above, with
evidence per PR.

## Rules

- **Process:** TDD; the full suite, build and boundary checks green before
  each push; merge only with `wait_pr.sh N && gh pr merge N --merge`; no
  attribution lines.
- **Real paths:** what is not reached from the daemon does not count (§11's
  rule).
- **Secrets:** read from the environment snapshot or the vault, never
  written to config or logs.

## Out of scope: product decisions

These are left as they were decided, or still wait for a decision:
- relay (Hermes's shared ingress for several bots);
- Kanban;
- plugins;
- provider OAuth (out since 18/11);
- image generation and the management dashboard (§10);
- MCP sampling, which needs a consent policy for a server asking Donkey's
  model to run;
- transactional turn resume, which needs a design decision: the journal was
  removed on purpose.

## Design changes requested (24/11)

### Streaming on the blocking executor

Today every streamed reply starts its own thread (`app/tool_loop_runtime`,
`spawnThread(runStreamJob, …)`). Moving it onto the shared executor as is
would let one long stream occupy a pool worker for its whole length and
starve Backtrail and recall. The change: give the executor streaming jobs.
- A job publishes partial results through a bounded queue that the caller
  drains.
- Streams get their own worker budget, so they can never take the workers
  that per-message calls need.
- The provider still builds its closures on the worker.

**Acceptance:**
- No thread is started per reply.
- Many concurrent streams leave Backtrail and recall answering within
  their deadlines.
- Cancelling a turn stops its stream.

### One way to keep a permanent connection (done: #170–#172)

Discord, QQ official and Slack socket mode each keep their own WebSocket
lifecycle, with different fixes:
- **Backoff:** Slack and Discord reset it after a good session; QQ only on
  READY.
- **Clean stop at shutdown:** only Slack has one.
- **Dead-connection detection:** Slack has an idle timeout and Discord
  watches for unacknowledged heartbeats; QQ has none, so a silent socket
  hangs it.
- **Fatal close codes:** Discord stops on them; QQ retries forever.
- **Logging:** QQ uses `echo` instead of the logger.

The change:
- **One facility** (`adapters/network/persistent_socket`) owns the thread,
  backoff with jitter, idle timeout, ping/pong and close, a stop that
  interrupts a blocked read, and logging.
- **A channel plugs in a protocol** as plain data and `nimcall` functions:
  how to find the URL, what to send on open, what a frame means (keep,
  reconnect, drop the session, stop), and what to do on each tick.
- **One "Discord-family" protocol** serves Discord and QQ official.

**Three PRs:**
1. The facility, with Slack moved onto it.
2. The Discord-family protocol, with Discord moved onto it.
3. QQ official moved onto the same protocol.

## Found during the recall work (not in this PRD)

- **"N days ago":** recall could turn relative dates into a time window
  (MAGMA's approach) and sort "when" answers by date.
- **Neighbour scores:** on time questions, recall sums them over all 64
  meaning matches, so filler can still win. That needs a design fix.
- **Failed replies:** a turn whose reply failed is never captured into
  memory.
- **Telegram polling:** done in #166, on the blocking executor.
- **`donkey-magma-index`:** nothing unique in it (an old checkout of #69);
  removed.

## Decisions (24/11)

1. **Item 2:** the read-only set is right (`session_search`, `current_time`,
   `calc`), and a consulted agent may use `web_search` and `fetch` where the
   user's web policy allows them.
2. **Item 6:** Azure OpenAI only; Vertex AI stays out.
3. **Item 5:** WhatsApp first.

## Deliverables

- one PR per item (item 5: one per group of WhatsApp cases);
- §12 of the coverage report;
- a short report: what closed, what stayed partial and why.
