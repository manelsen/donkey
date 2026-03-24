# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

*Add reusable patterns discovered during development here.*

---

## 2026-03-23 - US-031
- **Status**: Already implemented — verified acceptance criteria met
- **Files**: `src/donkey/adapters/channel/cli_repl.nim` (89 lines), `tests/ports/t_cli_repl.nim` (90 lines)
- **Verification**: `nim c --mm:orc src/donkey.nim` passes, `testament --megatest:off all` passes (all 68 tests green)
- **Learnings:**
  - CLI REPL adapter follows the standard channel adapter pattern: pure helpers (`isCommand`, `stripCommand`) + effectful adapter (`receive`, `send`, `ack`)
  - Single-user local adapter with fixed identity `UserId("local:cli")` and sequential message counter
  - pipeops usage: `?` operator for Result propagation in `sendReturnId` (`? a.send(msg)` chains fallible steps)
  - `splitChunks` from pipeops used for text chunking in `send`
  - `ChannelPort` concept satisfied by `receive*`, `send*`, `ack*` procs on `CliAdapter`
  - `editMessage` returns ok silently (CLI doesn't support editing)
  - Build note: `--styleCheck:error` and `warningAsError:on` are enforced via `config.nims`, no need to pass on CLI

---

## 2026-03-23 - US-030
- **Status**: Already implemented — verified acceptance criteria met
- **Files**: `src/donkey/adapters/channel/email.nim` (340 lines), `src/donkey/domain/channels/email_pure.nim` (148 lines), `tests/channel/t_email.nim` (272 lines)
- **Verification**: `nim c --mm:orc src/donkey.nim` passes, `testament --megatest:off all` passes (all tests green)
- **Learnings:**
  - Email adapter follows the standard channel adapter pattern: pure domain parser (`email_pure.nim`) + effectful adapter (`email.nim`)
  - IMAP polling uses `std/net` with SSL (port 993) — no external deps needed
  - SMTP sending supports both STARTTLS (port 587) and implicit TLS (port 465)
  - pipeops usage: `|>` for pure transforms (`raw |> parseEmail`, `searchResp |> parseSearchNums`), `|>->` for last-arg pipes (`headers |>-> findHeader("From")`), `>>=` for Result chains in IMAP/SMTP command sequences
  - Identity resolution maps email addresses to internal UserId UUIDs via TSV file persistence
  - `buildSmtpMessage` strips newlines from subject to prevent header injection
  - `ChannelPort` concept satisfied by `receive*`, `send*`, `ack*` procs on `EmailAdapter`
  - `OutboundChannelPorts` already has `email*` field wired in `ports/channel.nim`

---

