# PRD: Donkey v1.0 — The Sovereign Architecture (Pipeops Edition)

## 1. Visão Geral
Este PRD eleva o rigor arquitetural do projeto. O objetivo não é apenas implementar features do ecossistema, mas implementá-las **sob as restrições da topologia `pipeops.nim`** (Inspirado em OCaml/F#). Toda transformação deve ser conectada via `|>` ou `|>->` e toda falha IO encapsulada via `>>=`.

Total de Tarefas Atômicas: **71**

## 2. Quality Gates & Architectural Constraints
**Constraint Primária:** O uso do módulo `src/donkey/core/pipeops.nim` é mandatório.
- `|>`: Pipe forward (ex: `"hello" |> strip`). Requer funções unárias.
- `|>->`: Pipe last-arg (ex: `"world" |>-> surround("hello ")`). Requer target no último argumento.
- `>>=`: Monadic bind (ex: `readFile() >>= parseJson`). Usado para propagar `Result[T, E]` sem blocos `try/except`.

Estes comandos são absolutos para validar o CI:
- `nim build src --mm:orc --styleCheck:error --warnings:error` passes
- `testament pattern "tests/**/*.nim"` passes

## 3. User Stories

### US-001: Strict Compilation & Panics
**Contexto/Descrição:** Enforce Nim compiler strictness for zero-ambiguity.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Add --styleCheck:error, --warnings:error, --panics:on
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-002: Result[T, E] & Pipeops Pervasiveness
**Contexto/Descrição:** Eradicate try/except from business logic and enforce pipeops topology.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Ensure core/pipeops.nim is exported and used
- [ ] Refactor core to never raise, using `>>=` for chaining
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-003: Actor Model Mailbox
**Contexto/Descrição:** Resilient async message passing (inspired by BEAM/Pincer).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement lock-free or channel-based inbox/outbox in core/actor.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-004: System Diagnostics (Doctor)
**Contexto/Descrição:** CLI tool to verify external dependencies (DBs, binaries).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement `donkey doctor` checking for pgvector, docker, API keys
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-005: SSRF IP Validator (Pure)
**Contexto/Descrição:** Detect local/private/bogon IPs to prevent internal network scanning.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement network.nim with isPrivateIp() parsing logic
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-006: SSRF DNS Resolver
**Contexto/Descrição:** Resolve domains and block if they map to private IPs (nanobot style).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement safeResolve() adapter returning Result
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-007: Secret Scanner & Entropy
**Contexto/Descrição:** Detect API keys via Regex and Shannon Entropy (ironclaw style).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement secrets.nim with calculateEntropy() and regex masks
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-008: Output Sanitizer
**Contexto/Descrição:** Strip internal thought tags and mask secrets before user delivery.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement clean_response() via `|>` chaining
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-009: Cross-Channel Identity Map
**Contexto/Descrição:** Map unique users across different platforms (Donkey F1).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/identity.nim mapping platform IDs to internal UUIDs
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-010: Adaptive Debounce
**Contexto/Descrição:** Handle split messages based on timing/length (nullclaw style).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement pure message debounce/merge logic (1.2s to 8s window)
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-011: Hexagonal Channel Port
**Contexto/Descrição:** Define the abstract interface for all incoming/outgoing messages.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Create ports/channel.nim with send(), receive() Result signatures
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-012: Telegram Parser (Pure)
**Contexto/Descrição:** Parse TG updates into internal domain objects.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/channels/telegram_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-013: Telegram IO Adapter
**Contexto/Descrição:** HTTP long-polling or webhook adapter for TG.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/channels/telegram.nim using `>>=` for HTTP flows
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-014: Discord Parser (Pure)
**Contexto/Descrição:** Parse Discord gateway/webhook events.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/channels/discord_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-015: Discord IO Adapter
**Contexto/Descrição:** WebSocket or REST adapter for Discord.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/channels/discord.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-016: Slack Parser (Pure)
**Contexto/Descrição:** Parse Slack Events API payload.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/channels/slack_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-017: Slack Socket/Webhook Adapter
**Contexto/Descrição:** Socket Mode and Webhook support.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/channels/slack.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-018: WhatsApp Parser (Pure)
**Contexto/Descrição:** Parse WA Cloud API payloads.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/channels/whatsapp_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-019: WhatsApp Webhook Adapter
**Contexto/Descrição:** HTTP handler for WA.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/channels/whatsapp.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-020: Signal CLI DBus Adapter
**Contexto/Descrição:** Communicate with signal-cli daemon via IPC/DBus.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/channels/signal.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-021: WeChat/WeCom Parser
**Contexto/Descrição:** Handle WeChat XML/JSON quirks.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/channels/wechat_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-022: WeChat Webhook Adapter
**Contexto/Descrição:** HTTP handler for WeChat.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/channels/wechat.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-023: Feishu/Lark Parser
**Contexto/Descrição:** Handle Feishu event structures.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/channels/feishu_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-024: Feishu Webhook Adapter
**Contexto/Descrição:** HTTP handler for Feishu.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/channels/feishu.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-025: QQ Parser
**Contexto/Descrição:** Handle QQ official bot events.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/channels/qq_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-026: QQ Webhook Adapter
**Contexto/Descrição:** HTTP handler for QQ.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/channels/qq.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-027: DingTalk Parser
**Contexto/Descrição:** Handle DingTalk payloads.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/channels/dingtalk_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-028: DingTalk Webhook Adapter
**Contexto/Descrição:** HTTP handler for DingTalk.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/channels/dingtalk.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-029: Matrix Synapse Adapter
**Contexto/Descrição:** Client-server API for Matrix.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/channels/matrix.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-030: Email IMAP/SMTP Adapter
**Contexto/Descrição:** Polling IMAP for inbox, SMTP for outbox.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/channels/email.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-031: CLI REPL Interactive
**Contexto/Descrição:** Local terminal loop with history.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/channels/cli_repl.nim chaining via `>>=`
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-032: Web UI SSE Gateway
**Contexto/Descrição:** Real-time log and agent event streaming (Donkey F1).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Extend http_gateway.nim for bidirectional SSE
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-033: Hexagonal Provider Port
**Contexto/Descrição:** Define abstract LLM interface with streaming.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Create ports/provider.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-034: Provider Quirks Normalizer
**Contexto/Descrição:** Normalize message blocks across Anthropic/OAI/Gemini.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/providers/quirks.nim (pure)
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-035: OpenAI Protocol (Pure)
**Contexto/Descrição:** Format requests/responses for OpenAI/OpenRouter.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/providers/openai_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-036: OpenAI IO Adapter
**Contexto/Descrição:** HTTP client for OAI API.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/providers/openai.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-037: Anthropic Protocol (Pure)
**Contexto/Descrição:** Format XML/JSON for Claude APIs.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/providers/anthropic_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-038: Anthropic IO Adapter
**Contexto/Descrição:** HTTP client for Anthropic.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/providers/anthropic.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-039: Gemini Protocol (Pure)
**Contexto/Descrição:** Format requests for Google Gemini.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/providers/gemini_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-040: Gemini IO Adapter
**Contexto/Descrição:** HTTP client for Gemini.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/providers/gemini.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-041: Ollama Protocol (Pure)
**Contexto/Descrição:** Format requests for local GGUF models.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/providers/ollama_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-042: Ollama IO Adapter
**Contexto/Descrição:** HTTP client for Ollama.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/providers/ollama.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-043: DeepSeek Adapter
**Contexto/Descrição:** OpenAI-compatible wrapper with DeepSeek specific reasoning extraction.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/providers/deepseek.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-044: Zhipu/GLM Adapter
**Contexto/Descrição:** Adapter for Z.AI models.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/providers/zhipu.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-045: Smart Routing Classifier
**Contexto/Descrição:** Pure logic to pick provider based on task cost/complexity.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/routing/smart_route.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-046: Failover State Machine
**Contexto/Descrição:** Pure logic to handle API timeouts and fallback chains.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/routing/failover.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-047: Markdown Memory FS Sync
**Contexto/Descrição:** Sync MEMORY.md and USER.md to context (openclaw style).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/memory/markdown.nim using `>>=` for safe IO
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-048: SQLite Fast Cache
**Contexto/Descrição:** Store raw session logs locally for fast reboot.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/memory/sqlite_store.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-049: Text Chunking & Hashing
**Contexto/Descrição:** Pure logic to split text with overlap and SHA256 (openclaw style).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/memory/chunking.nim using `|>` chaining
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-050: Embedding Pipeline
**Contexto/Descrição:** Coordinate chunking with Provider Port to get vectors.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement core/memory/embedder.nim via `>>=` chaining
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-051: pgvector Adapter
**Contexto/Descrição:** PostgreSQL schema and IO for vectors.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/memory/pgvector_store.nim returning Result
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-052: Reciprocal Rank Fusion
**Contexto/Descrição:** Pure math to merge BM25 and Cosine Similarity scores (nullclaw style).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/memory/rrf.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-053: Temporal Decay Penalty
**Contexto/Descrição:** Pure logic to decay memory relevance over time.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/memory/decay.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-054: Triple Extraction Logic
**Contexto/Descrição:** Pure logic to parse Subject-Predicate-Object from text.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/memory/graph_pure.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-055: Apache AGE Adapter
**Contexto/Descrição:** Execute Cypher queries against PostgreSQL (Pincer style).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/memory/age_store.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-056: Silent Memory Turn
**Contexto/Descrição:** Background orchestrator loop to extract memories without user prompt (moltis).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement core/memory/silent_turn.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-057: Blackboard Scratchpad
**Contexto/Descrição:** Short-term planning memory injected into context (Supernova style).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement core/memory/blackboard.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-058: Native Tool Port
**Contexto/Descrição:** Abstract interface for tool execution.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Create ports/tool.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-059: Path Security Sandbox
**Contexto/Descrição:** Pure function to block `../` and restrict to workspace.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/tools/path_guard.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-060: File System Tools
**Contexto/Descrição:** Native read_file, write_file, list_dir.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/tools/fs.nim chained with `>>=`
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-061: Git Introspection Tools
**Contexto/Descrição:** Native git status, log, diff.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/tools/git.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-062: Safe Shell AST
**Contexto/Descrição:** Pure parser to detect/block shell operators (Pincer/Supernova style).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement domain/tools/shell_ast.nim blocking `;|&<>`
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-063: Native Shell Execution
**Contexto/Descrição:** Subprocess execution mapped to tool port.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/tools/shell.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-064: Web Fetch & DOM parse
**Contexto/Descrição:** Download HTML and convert to clean Markdown.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/tools/web_fetch.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-065: Headless Browser
**Contexto/Descrição:** Playwright/Puppeteer adapter for JS rendering and screenshots.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/tools/browser.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-066: Cron Scheduled Tasks
**Contexto/Descrição:** Background task scheduler (nanobot style).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement core/cron.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-067: MCP Client Protocol
**Contexto/Descrição:** Communicate with external Model Context Protocol servers over stdio.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement adapters/tools/mcp_client.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-068: Paddock: OS Limits
**Contexto/Descrição:** Cgroups/rlimit wrappers for CPU/RAM restriction.
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement infra/sandbox/limits.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-069: Paddock: Process Spawn
**Contexto/Descrição:** Spawn native tools in restricted child processes (moltis style).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement infra/sandbox/paddock.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-070: WASM Sandbox
**Contexto/Descrição:** Wasmtime integration for untrusted plugin execution (ironclaw style).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement infra/sandbox/wasm.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

### US-071: Docker Ephemeral Sandbox
**Contexto/Descrição:** Spawn isolated containers for arbitrary Python/Node code (nullclaw).
**Arch Rule:** ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.
**Acceptance Criteria:**
- [ ] Implement infra/sandbox/docker.nim
- [ ] Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable.
- [ ] nim build src --mm:orc --styleCheck:error --warnings:error passes
- [ ] testament pattern 'tests/**/*.nim' passes

