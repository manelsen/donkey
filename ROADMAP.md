# Donkey — Roadmap

Cada fase termina com algo que roda e é testável. Red-Green-Refactor em tudo.

Estado atual:

- base runtime/refactor concluída
- boundary refactor concluído
- `core/*` e `domain/*` em grande parte determinísticos
- próximo vetor principal: paridade funcional seletiva com IronClaw

---

## F0 — Scaffolding ✅

**Entregável:** `donkey --version` compila, testa e loga.

- [x] Projeto nimble: `donkey.nimble`, dependências (Chronos, nimcrypto, parsetoml)
- [x] Estrutura de diretórios: `src/core/`, `src/ports/`, `src/adapters/`, `src/app/`, `tests/`
- [x] Logger estruturado (nível, timestamp, contexto, sink intercambiável para testes)
- [x] Config loader: lê `donkey.toml`, aplica DONKEY_HOME, retorna defaults graciosamente
- [x] `SecretStore` port + `FileKeyStore` — **AES-256-GCM** (nimcrypto 0.7.3 removeu chacha20)
      Wire format: `enc2:<hex(iv[12] || ct || tag[16])>` — compatível com nullclaw enc2:
- [x] Contract tests para SecretStore (padrão nullclaw) — 2 implementações testadas
- [x] `testament --megatest:off all` — 20 testes passando
- [x] `donkey --version` e `donkey --help`

---

## F1 — Primeiro agente funcional ✅

**Entregável:** conversa real no Telegram com memória em `.md` e onboarding.

### Domain core
- [x] `ChatMessage`, `ConversationHistory`, `UserId`, `SessionId`
- [x] `CompletionRequest`, `CompletionResponse`
- [x] `buildPrompt/3`, `trimTo/2`, `needsOnboarding/1`
- [x] `parseOnboardingResponse/1` — extrai nome/callMe/tz/lang

### Ports
- [x] `ProviderPort` concept: `complete`, `caps`
- [x] `ChannelPort` concept: `receive`, `send`, `ack`
- [x] `MemoryPort` concept: `hasProfile`, `loadContext`, `saveUserMd`, `appendMemory`, `savePreferences`
- [x] `SecretStore` concept (F0)

### Adapters
- [x] `ZhipuAdapter` → `https://api.z.ai/api/coding/paas/v4`
  - Native tools (`web_search`, `code_interpreter`) em `caps()`
  - GLM-4-flash padrão, model configurável
- [x] `TelegramAdapter` — long polling getUpdates, offset tracking, Markdown
  - `IdentityResolver`: `telegram_user_id → UserId` (UUID persistido em TSV)
- [x] `MdFileAdapter` — paddocks em `~/.donkey/paddocks/{uuid}/`
  - USER.md, PREFERENCES.md, MEMORY.md, sessions/
  - `bootstrapUserMd` gera USER.md com YAML frontmatter

### Aplicação
- [x] `AgentRunner`: recebe mensagem → carrega contexto → chama provider → responde
- [x] Bootstrapping conversacional com marcador `ONBOARDING_COMPLETE`
  - Coleta nome, callMe, timezone, idioma
  - Cria USER.md ao final via `bootstrapUserMd`

### CLI
- [x] `donkey start` — daemon Telegram → Zhipu (TELEGRAM_BOT_TOKEN + ZHIPU_API_KEY)
- [x] `donkey ctl user list` — lista usuários no paddocks dir
- [x] `donkey ctl user show <uuid>` — exibe USER.md + PREFERENCES.md + MEMORY.md

**Testes:** 8 suites, 47 testes, todos verdes.

---

## F2 — MCP + Tools ✅

**Entregável:** agente executa ferramentas via MCP e skills Clawhub.

- [x] `ToolPort` concept: `listTools`, `invoke` (ToolSchema, ToolCall, ToolResult)
- [x] `McpClientAdapter` — cliente JSON-RPC 2.0 sobre stdin/stdout
- [x] `DenoSkillAdapter` — McpClientAdapter + sandbox Deno `--allow-*`
- [x] Integração no orchestrator: tool calls → ToolAgent → resultado → history
- [x] `donkey ctl tool install <mcp-server-cmd>` — registra MCP server
- [x] `donkey ctl skill install/list/update` — gestão de skills Deno
- [x] Tools injetadas no system prompt do orchestrator

### F2 — Revisão de segurança e robustez (2026-03)

- [x] **Function calling estruturado** (OpenRouter + Zhipu): `req.tools` serializado como array OpenAI format; response parsing extrai `tool_calls[{id, name, arguments}]`; `addAssistantWithToolCalls` registra turn antes de tool results
- [x] **Paddock por usuário**: `~/.donkey/paddocks/{uuid}/` — isolamento de filesystem entre usuários
- [x] **Path enforcement**: `resolveInPaddock` (string-based, zero syscall) + `inPaddock` — rejeita paths fora do paddock
- [x] **Symlinks ignorados**: `pcLinkToFile`/`pcLinkToDir` → `discard` em `walkFind` e `grepDir` — sem traversal para fora do paddock
- [x] **Docker sandbox**: `sandbox.nim` com `buildDockerCmd` + `sandboxBash`; bind mount paddock em `/workspace`; `smNone`/`smDocker` configuráveis em `donkey.toml [sandbox]`
- [x] **Config `[sandbox]`**: `SandboxMode` enum em `config/types.nim`; loader parseia `mode` e `image`; default `smNone` + `alpine`
- [x] **Startup warning**: `sandboxLogLevel` emite warn se smNone, info se smDocker
- [x] **Suite de testes native tools**: 70+ testes determinísticos cobrindo `resolveInPaddock`, `inPaddock`, `performBash`, `read_file`/`edit_file` com hashline anchors, `performFind`, `performGrep`, `applyTodoOps`, jobs e `executeNativeTool`

---

## F3 — Multi-provider ✅

**Entregável:** 5 providers funcionando com suas peculiaridades isoladas nos adapters.

### Pronto
- [x] `OpenRouterAdapter`, `AnthropicAdapter`, `GeminiAdapter`, `MiniMaxAdapter`, `ZhipuAdapter` — completions básicas
- [x] Seleção de provider por usuário em `PREFERENCES.md` (inline keyboard `/models` com dois níveis)
- [x] Fallback automático: `buildFallbackFn` + fallback chain por sessão
- [x] `donkey ctl provider test <name>`

### Fechado
- [x] **Anthropic function calling**: request serializa tools; resposta parseia `tool_use`; histórico usa `tool_result`
- [x] **Gemini function calling**: body inclui `functionDeclarations`; resposta parseia `functionCall`; histórico respeita `requiresUserFirst`
- [x] **Streaming real**: OpenRouter e Anthropic usam SSE real; o orquestrador evita streaming no primeiro round quando há tools

---

## F4 — Multi-agente ✅

**Entregável:** orchestrator delega para workers especializados via message passing.

- [x] `AgentMessage` type (amkTask, amkCancel, amkResult, amkError)
- [x] `OrchestratorAgent` + `MemoryAgent` + `ToolAgent` — actors com AsyncQueue inbox
- [x] Cancelamento em cascata via amkCancel
- [x] Native tools Zhipu via `caps()` (web_search, code_interpreter)
- [x] Streaming via OS thread + Channel[string] + partials no globalOutbox

### F4 — Revisão de robustez (2026-03)

- [x] **Detecção de repetição**: `recentCalls: seq[(tool, args)]`; aborta se mesmo `(toolName, inputJson)` visto ≥ 2 vezes — substitui `MaxToolRoundsOrch = 5`
- [x] **Hard cap elevado**: `MaxToolRoundsOrch = 50` como safety net
- [x] **Progress embed**: após cada tool call, `isPartial=true` com `streamId&"-st"`; fecha com `isPartial=false` e contagem total ao final do loop
- [x] **Sandbox integrado**: `paddockDir` criado em `runOrchestrator`; `sandboxMode`/`sandboxImage` passados do config para `NativeCtx`
- [x] **`ask` isolado do inbox principal**: sessão agora usa `askInbox` dedicado, sem competir com mensagens normais do actor
- [x] **Correlação explícita de workers**: replies de memória e tools usam filas distintas (`memOut` / `toolOut`) e validação por `id`
- [x] **Persistência periódica de sessão**: snapshot salvo ao final de cada `tkUserMsg`, não só em cancel/reset
- [x] **Runtime efêmero rebuildável**: drift em tools/skills/provider surface recria só o actor da sessão, preservando memória persistente
- [x] **`schedule_reminder` unificada**: reminder saiu do special-case do orquestrador e segue o caminho normal de tools nativas

---

## F5 — Discord + Cross-channel ✅

**Entregável:** usuário continua conversa do Telegram no Discord sem perder contexto.

- [x] `DiscordAdapter` — gateway WebSocket próprio (ws_client.nim, RFC 6455)
- [x] `IdentityResolver` multi-canal: `(ChannelKind, rawId) → UserId`
- [x] `SessionManager` multi-canal com `recordChannel`
- [x] `/continue` no Telegram + `/continue` modal no Discord
- [x] `/mycode` cross-channel OTP com TTL 10 min
- [x] `donkey ctl session list <user>`
- [x] Session keying por `chat_id` em grupos Telegram

---

## F6 — Postgreyskull ✅ (pgvector + AGE)

**Entregável:** memória semântica e relacional substituindo os `.md` como backend.

- [x] `PostgresMemoryAdapter` implementando `SemanticMemoryPort` (`-d:withPostgres`)
  - Schema: `donkey_memories` (pgvector `vector(4096)`, IVFFlat index)
  - `hasProfile`, `loadContext`, `saveUserMd`, `appendMemory`, `savePreferences`
  - `search()`: hybrid vector cosine + AGE graph enrichment
  - `importFromMd()`: migração de paddock `.md` → Postgres
- [x] Apache AGE graph `donkey_graph`:
  - Labels: Memory, Person, Concept, Fact, Solution, Session, Task, Preference
  - Edges: HAS_MEMORY, ABOUT, FROM, RESOLVES, USES, CONTINUED_IN, KNOWS, HAS_PREFERENCE
  - `graphUpsertSession`, `graphLinkSessions`, `graphAddFact`, `graphAddPerson`, `graphTraverse`
- [x] `OpenRouterEmbeddingAdapter`: POST /v1/embeddings, Qwen/Qwen3-Embedding (4096-dim)
- [x] `donkey ctl memory search <user> "<query>"` + `ctl memory import <user>`
- [x] `.md` como views/exports do grafo sob demanda via `donkey ctl memory export`

---

## F7 — Skills Ecosystem ✅ no plano de CLI/runtime-base

**Entregável:** marketplace Clawhub integrado, skills por usuário.

### Infra local — pronto
- [x] `SkillManifest`: nome, versão, script, tools, permissões Deno
- [x] `DenoSkillAdapter`: `McpClientAdapter` + `deno run <permissions> <script>`
- [x] Registry global: `config/skills.toml`; per-user: `data/users/{uuid}/skills/`
- [x] `mergeSkills`: user skills override global registry por nome
- [x] `loadUserSkills`: carrega skills por usuário

### Clawhub marketplace — entregue no CLI
- [x] HTTP client para o registry remoto Clawhub (busca, listagem)
- [x] Download de skill + verificação de hash/assinatura
- [x] `donkey ctl skill search <query>` — pesquisa no registry remoto
- [x] `donkey ctl skill install <slug>` via registry remoto
- [x] `donkey ctl skill update` — compara versões locais com registry
- [x] User skills mergeadas no bootstrap de sessão

### Próximo passo além da fase
- [ ] Tornar bundles remotos do ClawHub executáveis no mesmo fluxo das skills Deno locais, sem depender só do lock/install no CLI

---

## F8 — Channels chineses ✅ no runtime base

**Entregável:** WeCom + Feishu funcionais; WeChat e QQ mapeados.

- [x] `WeComAdapter` — Webhook HTTP + API corporativa (corp_id, corp_secret, agent_id)
- [x] `FeishuAdapter` — WebSocket gateway + Lark Open API
- [x] `WeChatAdapter` — Official Account API (OAuth 2.0, template messages)
- [x] `QQAdapter` — OneBot v11 HTTP

### Limitação atual
- [ ] Ingress próprio desses canais ainda depende de forwarding externo para os adapters, em vez de um servidor dedicado embutido no daemon

---

## F9 — TUI + Admin ✅

**Entregável:** interface terminal para operação do daemon.

- [x] IPC endpoint Unix socket (`~/.donkey/donkey.sock`) — line-delimited JSON
  - Commands: `status` → DaemonStatus JSON; `logs` → ring buffer snapshot
  - Chronos async server (`app/ipc_server.nim`), sync client (`adapters/ipc/client.nim`)
- [x] Log ring buffer (500 entries, Lock-protected) in `core/log.nim` — `ringInit()` / `ringSnapshot(n)`
  - Default sink writes to stderr AND pushes to ring; CLI tools skip ring (ringInit not called)
- [x] `donkey ctl status` — snapshot: uptime, sessions, channels, providers, tools, memory backend
- [x] `donkey tui` — live illwill dashboard (Users · Sessions · Logs · Stats)
  - Auto-refresh every 2s via IPC socket; keys: q=quit, tab=next panel, r=force refresh
- [x] Deploy templates generalizados em `deploy/` — unit/env/config renderizados por variáveis centrais
- [x] `deploy/install.sh` — script standalone (sem root): cria dirs, instala binary, config, registra service
- [x] `donkey service install` — instala como systemd --user; injeta keys do processo atual automaticamente
- [x] `donkey service remove` — desregistra service; preserva config e dados
- [x] `donkey service start / stop / restart` — wraps systemctl --user
- [x] `donkey service logs [-f] [--cat]` — journalctl --user; `-f` segue; `--cat` sem metadata
- [x] User manager panel básico (listar usuários no TUI; editar/revogar via `ctl`)
- [x] `donkey ctl` expandido consolidado com os comandos de F1-F9 já disponíveis no binário

### Próximo passo além da fase
- [ ] Ações administrativas interativas diretamente no TUI

---

## Decisões abertas

- [ ] **F6:** `.md` como views do grafo — automáticas ao fechar sessão ou exportadas via `ctl memory export`?
- [ ] **F8:** QQ — OneBot v11/v12 ou API oficial?

### Fechadas

- **F1 long polling vs webhook** → config `[telegram] webhook_url` presente → webhook; ausente → long polling
- **F2 manifesto de skill** → `SkillManifest` em `skills.toml [[skill]]`; Clawhub integration é problema de F7
- **F4 workers** → on-demand: `asyncSpawn` fire-and-forget por sessão
- **Base runtime/refactor** → concluída: daemon, orchestrator, native tools, loader, bootstrap, sandbox, outbound e runtimes de canal já foram fatiados e cobertos por testes de contrato
- **Boundary / functional core** → concluído: regras de ingresso, onboarding, tool loop, outbound, command routing e dispatch nativo foram para `core/*`; `domain/*` ficou sem `proc`

---

## Próximo ciclo sugerido

Ver também [`IRONCLAW_PARITY.md`](/home/micelio/git/donkey/IRONCLAW_PARITY.md).

1. Hardening de segurança
   - prompt injection via tool output
   - allowlist explícita de endpoints
   - troca de `std/sha1` deprecated no WeChat

2. Fechar inbound real de canais novos
   - WeChat
   - QQ / OneBot

3. Gateway contínuo
   - HTTP/Web gateway com SSE/WebSocket
   - broadcast de eventos do runtime

4. Inteligência operacional
   - smart model routing com telemetry, UI de modo `auto`, budget policy declarada, feedback recente persistido por rota e preferência por pricing conhecido
   - heartbeat / execução proativa
   - próximo provider local provável: Ollama
