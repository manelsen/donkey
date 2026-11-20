[PRD]
# PRD: Cross-Channel Command Dispatch in the Application Layer

## Overview

PR #73 replaced seven copies of the text-command `case command.route` tree
(Feishu, WeChat, WhatsApp, WeCom, QQ, Slack, Discord) with one
`dispatchTextCommand`. That removed the duplication, but it left the
dispatcher where the copies lived: `src/donkey/adapters/channel/`.

This breaks the boundary rule in `CLAUDE.md`: "`adapters` traduzem I/O externo
para `ports`; não carregam semântica cross-channel ou decisão de negócio".
The dispatcher decides session operations, mutates preferences, consumes link
codes and enqueues tasks. It depends on concrete adapters (`MdFileAdapter`,
`IdentityResolver`). Its support module `common_runtime.nim` (≈950 lines,
75 procs, 27 references to `MdFileAdapter`) holds the reply builders for
`/about`, `/doctor`, `/status`, `/models`, `/think`, `/budget` and others.
Those builders are business logic that sits in the adapter layer.

The CodeRabbit review of #73 found several defects that predate the PR.
They come from the same cause: each channel decides command policy for
itself, so each one can get it wrong:

| Defect | Cause |
|---|---|
| Discord posts `/mycode`, `/doctor`, `/memory` replies in the public channel. Anyone in the server can read a link code and `/continue` into the victim's session. | Visibility is decided per channel. Discord ignores `CommandReply.sensitive`. |
| `/stop` on text channels only enqueues `tkStop`. It does not interrupt the running turn. | Only Telegram calls `requestTurnInterrupt`. |
| Discord slash commands that enqueue a session task get no initial interaction response, so the client shows "interaction failed". | The ack obligation is not part of the outcome contract. |
| `/compact` with no session replies "Nenhuma conversa ativa para reiniciar". | The no-session text is a two-way `if`. It is not tied to the command. |
| Feishu `/help` lists `/config`, which Feishu answers with nothing. | Help is not filtered by channel capability. |
| The Slack `/config` fallback says "use os botões abaixo" in a message that has no buttons. | The presentation fallback reuses the interactive copy. |
| `/memory` raises `IOError` out of the drain loop when the file is unreadable. | The builder does I/O without returning `Result`. |

This PRD moves command *policy* into `app/`, behind ports. Adapters keep two
jobs: turning a channel event into a command request, and presenting a
`CommandReply`.

## Goals

- One command dispatcher for **every** channel, Telegram included, living in `app/` and depending only on `ports/`, `core/` and `domain/`.
- Reply visibility (public vs. requester-only) and the ack obligation are part of the dispatcher's output contract, not per-channel conventions.
- Shared turn-interrupt policy: a command that interrupts a turn does so on every channel.
- Channel capabilities decide which commands are offered (help) and which are answered.
- Reply builders that read files return `Result`; no exception leaves a drain loop.
- `common_runtime.nim` shrinks to channel-presentation helpers only.
- Behaviour visible to users is unchanged, except where this PRD fixes one of the defects above.

## Quality Gates

These commands must pass for every user story:
- `nim c --mm:orc src/donkey.nim`
- `bash scripts/check_boundaries.sh`
- `bash scripts/run_tests.sh`

Stories touching a specific runtime also run that runtime's tests directly, e.g.:
- `nim c -r tests/adapters/channel/t_text_command_dispatch.nim`
- `nim c -r tests/adapters/channel/t_dm_gate_runtimes.nim`
- `nim c -r tests/adapters/channel/t_telegram_runtime.nim`
- `nim c -r tests/channel/t_discord.nim`

## User Stories

### US-001: Command outcome contract in core
**Description:** As a maintainer, I want the dispatcher's output to say *who may see* a reply and *whether the channel owes an acknowledgement*, so that channels can't silently get privacy or ack semantics wrong.

**Acceptance Criteria:**
- [x] `CommandReply`, `ReplyTopic` and `CommandOutcome` move to a pure `core/commands/` module.
- [x] `sensitive: bool` is replaced by `visibility: ReplyVisibility` (`rvPublic`, `rvRequesterOnly`).
- [x] `cokSilent` is replaced by an outcome stating the request was accepted. Channels with an interaction protocol (Discord slash commands, Slack slash commands) must ack it.
- [x] Pure tests cover the topic → visibility mapping for every local action (`/mycode`, `/continue`, `/doctor`, `/memory`, `/whoami` are requester-only).

### US-002: Ports for what commands need
**Description:** As a maintainer, I want the dispatcher to depend on ports, so that `app/` can host it without importing adapters (enforced by `check_boundaries.sh`).

**Acceptance Criteria:**
- [x] Every memory operation the commands use (memory view, clear, channel prefs, model/think/budget prefs, skill entries) is reachable through `MemoryRuntimePort` or a new narrow port. Fallible operations return `Result`.
- [x] Link code generation and consumption go through `LinkCodePort` (already in `ports/link_codes.nim`).
- [x] The model catalog, provider ping and doctor report are injected as function fields. They are not imported from adapters.
- [x] `MdFileAdapter` and `IdentityResolver` provide the new ports. No call site constructs them inside the dispatcher.

### US-003: Move the dispatcher to `app/command_dispatch.nim`
**Description:** As a maintainer, I want command policy in the application layer, so that adapters are back to pure I/O translation.

**Acceptance Criteria:**
- [x] `app/command_dispatch.nim` exposes `dispatchCommand(env, sessions, request): CommandOutcome`, where `env` holds only ports and plain values.
- [x] `adapters/channel/text_command_dispatch.nim` is deleted. Runtimes import the app module, which the dependency direction allows: adapters → app.
- [x] `tests/architecture/t_boundaries.nim` gains a check that `app/command_dispatch.nim` imports no `adapters/` module.
- [x] `t_text_command_dispatch.nim` moves to `tests/app/` and runs against fake ports. No files are written on disk.

### US-004: Shared turn-interrupt policy
**Description:** As a user, I want `/stop` (and other interrupting commands) to stop the running answer on every channel, so that Telegram is not the only channel where it works.

**Acceptance Criteria:**
- [x] The dispatcher calls `requestTurnInterrupt` before enqueueing when `interruptsTurn(command.kind)` holds.
- [x] Telegram's local copy of that branch is removed in favour of the shared one.
- [x] A test with a busy session asserts that the stop flag is set before the task is enqueued, for at least one non-Telegram channel kind.

### US-005: Per-command no-session text
**Description:** As a user, I want an accurate message when a session command has no session to act on.

**Acceptance Criteria:**
- [x] The no-session text is chosen per `CommandKind` from a pure table. `/compact`, `/stop` and `/debug` do not say "reiniciar".
- [x] A pure test asserts that every session-task command has a no-session text.

### US-006: Capability-aware help and command availability
**Description:** As a user, I want `/help` to list only commands this channel can actually answer.

**Acceptance Criteria:**
- [x] `ChannelCapabilityDescriptor` gains the command-surface capabilities it needs (at least `configUi`, `interactiveMenus`).
- [x] `buildHelpText` takes the descriptor and omits commands the channel answers with `rtUnsupported`.
- [x] A test iterates over all `ChannelKind` values and asserts that every command listed in help is dispatched to something other than `rtUnsupported`.
- [x] The Slack `/config` text fallback names `/models`, `/think` and `/budget` instead of buttons.

### US-007: Requester-only replies are never public
**Description:** As a user, I want link codes, diagnostics and memory dumps sent only to me, so that other members of a group or server cannot read them or take over my session.

**Acceptance Criteria:**
- [x] Discord: on interactions, `rvRequesterOnly` replies use the ephemeral flag. On text events they are sent by DM.
- [x] Group contexts on Slack, QQ, Feishu, WeCom and WeChat: a requester-only reply goes through the channel's private path. If the channel has none, the bot replies publicly with a fixed notice ("envie este comando em mensagem direta") and never with the content.
- [x] If the private send fails, the content is **not** posted publicly as a fallback.
- [x] Tests per channel prove that a requester-only reply in a group context never reaches the public send path.

### US-008: Discord interactions are always acknowledged
**Description:** As a user, I want Discord slash commands that start a task to show as successful.

**Acceptance Criteria:**
- [x] Every outcome for an event with `interactionId` produces exactly one initial interaction response within the handler. An accepted task gets a short ephemeral confirmation.
- [x] A test with a fake Discord adapter asserts one interaction response per slash event across all outcome kinds.

### US-009: Migrate Telegram onto the shared dispatcher
**Description:** As a maintainer, I want Telegram to stop carrying its own command tree.

**Acceptance Criteria:**
- [x] `handleTelegramTaskCommand` and the Telegram local-action tree call `dispatchCommand`. Telegram keeps only presentation (markdown, keyboards, reply targets, progress feedback text).
- [x] Telegram-only behaviours (session auto-creation for `/debug`, `/reset`, `/new`, …) become explicit dispatcher options, not a second code path.
- [x] Existing Telegram runtime tests pass unchanged, or are updated only where this PRD changes behaviour on purpose.

### US-010: Shrink `common_runtime.nim`
**Description:** As a maintainer, I want the remaining adapter-side helpers to be presentation only.

**Acceptance Criteria:**
- [x] Pure text builders (help, about, status, ping, deferred UI text) move to `core/commands/` or `domain/`.
- [x] Builders that read files return `Result[string, string]`. `buildMemoryViewText` on an unreadable file yields an error reply, not an exception.
- [x] `common_runtime.nim` has no reference to `MdFileAdapter` outside wiring helpers, or is removed.

## Functional Requirements

- FR-1: One dispatcher decides the reply for every command on every channel.
- FR-2: The dispatcher depends only on `core`, `domain` and `ports`.
- FR-3: Requester-only replies are never posted to a shared space, on any failure path.
- FR-4: Interrupting commands interrupt the active turn before the task is enqueued.
- FR-5: Interaction-based channels always receive an initial response.
- FR-6: Help lists only commands the channel can answer.
- FR-7: No exception escapes a channel drain loop from command handling.

## Non-Goals

- WeCom encrypted callback mode (`EncodingAESKey`, AES-CBC decryption, four-value `msg_signature` including `Encrypt`/`echostr`). This is a channel feature gap, not a dispatch concern. It needs its own PRD. Today the WeCom listener accepts only plaintext-mode callbacks.
- Changing the command catalogue, command names or reply wording beyond the defects above.
- Presentation-surface work (slots, editable menus). See `prd-outbound-ui-decoupling.md`.
- Converting every `respond`/send helper in the embedded webhook listeners to `Result`. This can follow separately.

## Technical Considerations

- `scripts/check_boundaries.sh` forbids `app/` from importing `adapters/`. US-002 must land before US-003.
- Dispatch runs from synchronous drain procs. Keep it sync and `gcsafe`. Ports that wrap Chronos calls must not leak `{.async.}` into the dispatcher. See the Chronos notes in `CLAUDE.md`.
- `SessionManager` already lives in `app/`. Session-task enqueueing (`enqueueSessionTask`) moves with the dispatcher unchanged.
- `domain/` modules currently return `Result` in about 19 files. `CLAUDE.md` says domain `func`s carry no `Result`. Settle this with an ADR before adding more. The review flagged `imapQuote` and `oneBotListenerCheck`.
- Order to reduce risk: US-001 → US-002 → US-003 (pure moves, no behaviour change) → US-004…US-008 (fixes, each with its regression test) → US-009 → US-010.

## Success Metrics

- Exactly one `case command.route` in `src/` outside `core/commands/`.
- `rg 'MdFileAdapter|IdentityResolver' src/donkey/app/command_dispatch.nim` returns nothing.
- `common_runtime.nim` has 300 lines or fewer, or is removed.
- Each defect in the Overview table has a regression test that fails on today's code.

## Open Questions

- For channels with no private path in group context, should a requester-only command refuse ("use DM") or send a one-time private link if the platform offers one?
- Should `/whoami` be requester-only? It leaks internal user and session ids.
- Should Telegram's progress texts (e.g. "🗜️ Compactando histórico...") become dispatcher replies for all channels, or stay Telegram presentation?
- Does `Result` belong in `domain/`? See the ADR note above.

## Implementation Notes

Implemented on `feat/command-dispatch-app`.

- **Contract** (`core/commands/command_outcome.nim`): visibility comes from the topic (`topicVisibility`), so a channel cannot mark a reply public by mistake. `cokAccepted` carries the command kind; `acceptedText` is the ack text, and it is also Telegram's progress text. `routeReply` / `replyDelivery` decide conversation, private path or notice, and never fall back from a failed private send to the shared space.
- **Ports**: `CommandServicesPort` (`ports/command_services.nim`), with every effect returning `Result`, and `IdentityLinkPort` (`ports/link_codes.nim`), which mints a code and links the speaker's raw id. `LinkCodePort` alone was not enough because redeeming has to write the identity mapping. The adapters provide them through `newCommandServices` (`adapters/channel/command_services.nim`) and `identityLinkPort` (`identity_resolver.nim`). The `guarded` template turns any exception into `err`.
- **Dispatcher** (`app/command_dispatch.nim`): `dispatchCommand(env, sm, msgSeq, request)`. `dispatchUiCommand` serves the text forms of picker commands without a session. Session behaviour is `SessionMode` (`smRequireLive` / `smCreate`) plus an optional `ensureSession` hook (US-009).
- **Capabilities**: the descriptor gained `configUi`, `interactiveMenus` and `repliesToRequester`. `/whoami`, `/reasoning`, `/tasks`, `/agents` and `/poll` are now answered by the dispatcher on every channel. Only `/config` and `/menu` depend on the channel. That is how help and availability line up: help no longer has to hide commands that a channel could answer in text.
- **Presentation**: Discord goes through `DiscordReplySink` (`presentDiscordOutcome`). Telegram goes through `presentTelegramOutcome` / `telegramReplyText`. QQ and Telegram groups refuse requester-only commands *before* dispatching, so a link code is never minted or consumed where its answer cannot be shown.
- **Split of `common_runtime.nim`** (951 → 88 lines): pure texts went to `core/commands/command_text.nim`, preferences to `adapters/memory/channel_prefs_store.nim`, model pickers to `adapters/channel/model_catalog_ui.nim`, and MdFile-backed effects to `adapters/channel/command_services.nim`. `common_runtime` re-exports them for existing callers and keeps only UI slots and wiring (`ChannelRuntimeEnv`).

### Decisions on the open questions

- No private path in a group: the bot refuses with `RequesterOnlyNotice` ("Envie este comando em mensagem direta.") and does not send a one-time link.
- `/whoami` is requester-only.
- Progress texts: `acceptedText` lives in core. Telegram sends it for every accepted task and Discord uses it as the ephemeral ack. Plain-text channels stay silent, as before.
- `Result` in `domain/`: still open. This PRD added no `Result` to `domain/`.

### Regression tests per defect

| Defect | Test |
|---|---|
| Discord public `/mycode` | `tests/adapters/channel/t_discord_command_replies.nim` |
| `/stop` without interrupt | `tests/app/t_command_dispatch_app.nim` ("/stop on a busy non-Telegram session…") |
| Discord interaction without ack | `t_discord_command_replies.nim` ("every outcome kind produces exactly one…") |
| `/compact` no-session text | `tests/core/t_command_outcome.nim`, `t_command_dispatch_app.nim` |
| Feishu `/help` lists `/config` | `t_command_dispatch_app.nim` (capabilities suite) |
| Slack `/config` fallback mentions buttons | `t_command_dispatch_app.nim` ("the /config text fallback…") |
| `/memory` raising `IOError` | `tests/adapters/channel/t_common_runtime.nim` (unreadable memory file) |

[/PRD]
