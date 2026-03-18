# Donkey — Roadmap

Cada fase termina com algo que roda e é testável. Red-Green-Refactor em tudo.

---

## F0 — Scaffolding ✅

**Entregável:** `donkey --version` compila, testa e loga.

- [x] Projeto nimble: `donkey.nimble`, dependências (Chronos, nimcrypto, parsetoml)
- [x] Estrutura de diretórios: `src/core/`, `src/ports/`, `src/adapters/`, `src/app/`, `tests/`
- [x] Logger estruturado (nível, timestamp, contexto, sink intercambiável para testes)
- [x] Config loader: lê `donkey.toml`, aplica DONKEY_HOME, retorna defaults graciosamente
- [x] `SecretStore` port + `FileKeyStore` — AES-256-GCM (nimcrypto)
- [x] Contract tests para SecretStore
- [x] `donkey --version` e `donkey --help`

---

## F1 — Primeiro agente funcional ✅

**Entregável:** conversa real no Telegram com memória em `.md` e onboarding.

- [x] Domain: `ChatMessage`, `ConversationHistory`, `UserId`, `SessionId`
- [x] Domain: `CompletionRequest`, `CompletionResponse`, `buildPrompt`, `trimTo`
- [x] Domain: `parseOnboardingResponse`, `needsOnboarding`
- [x] `ProviderPort` concept: `complete`, `caps`
- [x] `ChannelPort` concept: `send`, `receive`, `ack`
- [x] `MemoryPort` concept: `hasProfile`, `loadContext`, `saveUserMd`, `appendMemory`, `savePreferences`
- [x] `ZhipuAdapter` — `https://api.z.ai/api/coding/paas/v4`, native tools em `caps()`
- [x] `TelegramAdapter` — long polling, offset tracking, `IdentityResolver` (telegram_id → UUID)
- [x] `MdFileAdapter` — paddocks em `~/.donkey/paddocks/{uuid}/`, `bootstrapUserMd`
- [x] `AgentRunner`: mensagem → contexto → provider → resposta
- [x] Bootstrapping conversacional com marcador `ONBOARDING_COMPLETE`
- [x] `donkey start`, `donkey ctl user list`, `donkey ctl user show <uuid>`

---

## F2 — MCP + Tools ✅

**Entregável:** agente executa ferramentas via MCP e skills Deno/Clawhub.

- [x] `ToolPort` concept: `listTools`, `invoke` (ToolSchema, ToolCall, ToolResult)
- [x] `McpClientAdapter` — JSON-RPC 2.0 sobre stdin/stdout, `initialize`, `tools/list`, `tools/call`
- [x] `DenoSkillAdapter` — wrapper sobre McpClientAdapter para subprocessos Deno com `--allow-*`
- [x] `ToolsRegistry` — `tools.toml` com entradas `[[tool]]` (kind, command, args, permissions)
- [x] Integração no `AgentRunner`: tool calls → executa → devolve resultado ao provider
- [x] Tool list injetada no system prompt
- [x] `donkey ctl tool install <mcp-server-cmd>`
- [x] `donkey ctl skill install <script.ts> [--allow-*]`

---

## F3 — Multi-provider ✅

**Entregável:** 5 providers com suas peculiaridades isoladas nos adapters.

- [x] `OpenRouterAdapter` — `HTTP-Referer`, `X-Title`, formato OpenAI
- [x] `AnthropicAdapter` — `system` top-level, `x-api-key`, `anthropic-version`, `tool_use`/`tool_result` blocks
- [x] `GeminiAdapter` — role `"model"`, `systemInstruction`, auth via `?key=`, normalização de histórico
- [x] `MiniMaxAdapter` — M2 series, OpenAI-compatible
- [x] `CompleteFn` — closure que envolve qualquer adapter para desacoplamento
- [x] Seleção de provider por usuário em `PREFERENCES.md` (TOML: `provider`, `model`)
- [x] Fallback: provider primário falha → tenta lista de fallbacks em ordem
- [x] `donkey ctl provider test <name>`

---

## F4 — Multi-agente ✅

**Entregável:** orchestrator delega para workers via Chronos message passing.

- [x] `AgentMessage` (variant: task, result, error, cancel) + construtores
- [x] `OrchestratorAgent` — `AsyncQueue` inbox, carrega contexto, loop de tool calls (max 5 rounds)
- [x] `MemoryAgent` — worker persistente: `loadCtx`, `saveMem`, `savePrefs`
- [x] `ToolAgent` — worker persistente: `invokeTool` via McpClientAdapter
- [x] Re-prompt automático quando LLM retorna resposta vazia
- [x] Cancelamento em cascata: `amkCancel` → orchestrator → workers
- [x] `startDaemon` sync + `dispatchMsg` async (um `waitFor` por mensagem)
- [x] `HttpPort` + `StdHttpAdapter` — transporte HTTP intercambiável (prep para IoT)

---

## F5 — Discord + Cross-channel

**Entregável:** usuário continua conversa do Telegram no Discord sem perder contexto.

- [x] `DiscordAdapter` — gateway WebSocket, slash commands
- [x] `IdentityResolver` generalizado: `(ChannelType, channel_user_id) → UserId`
- [x] `SessionManager` multi-canal: sessão tem `seq[ActiveChannel]`
- [x] `/continue` em qualquer canal — reanexar sessão ativa
- [x] `donkey ctl session list <user>`

---

## F6 — Postgreyskull

**Entregável:** memória semântica e relacional substituindo os `.md` como backend.

- [x] PostgreSQL + pgvector + Apache AGE
- [x] Schema do grafo (nós `memory_nodes`, grafo AGE `donkey`, vertices `:Memory`)
- [x] `PostgresMemoryAdapter` implementando `MemoryPort` + `SemanticMemoryPort`
- [x] Pipeline de embedding: texto → `qwen/qwen3-embedding` → vetor (4096 dim, OpenRouter)
- [x] Busca vetorial por similaridade coseno (pgvector IVFFlat); AGE pronto para arestas
- [x] Migração: `importFromMd` importa paddock `.md` para Postgres
- [x] `donkey ctl memory search <uuid> "<query>"` e `ctl memory import <uuid>`

---

## F7 — Skills Ecosystem ✅

**Entregável:** skills por usuário com versionamento.

- [x] `SkillManifest`: nome, versão, permissões Deno, tools expostas
- [x] Registry local: `config/skills.toml`
- [x] Per-user override: `data/users/{uuid}/skills/skills.toml`
- [x] `donkey ctl skill list`, `donkey ctl skill update`

---

## F8 — Channels chineses ✅

**Entregável:** WeCom funcional; WeChat e QQ mapeados.

- [x] `WeComAdapter` — Webhook + API corporativa
- [x] `WeChatAdapter` — Official Account API, OAuth 2.0 (stub mapeado)
- [x] `QQAdapter` — OneBot protocol (stub mapeado)

---

## F9 — TUI + Admin

**Entregável:** interface terminal para operação do daemon.

- [ ] TUI (`illwill` ou similar): dashboard, log viewer, user manager
- [ ] Health check via Unix socket local
- [ ] `donkey ctl status`

---

## IoT / RPi Zero (paralelo a F5+)

**Entregável:** binário estático ~1MB sem dependências de runtime.

- [ ] `ChronosHttpAdapter` — `chronos/apps/http` + `nim-bearssl` (sem OpenSSL)
- [ ] Build com `musl-gcc --passL:"-static"`
- [ ] Validação no RPi Zero (512MB RAM, ARMv6)

---

## Decisões abertas

- [ ] Clawhub skill manifest format — verificar quando o ecossistema existir

## Decisões fechadas

- **Long polling vs. webhook** — polling para sempre. Latência do poll (~300ms) some no ruído da latência do provider (2–10s). Webhook traria complexidade sem contrapartida perceptível.
- **`.md` e grafo em F2+** — coexistem como camadas independentes de memória. `.md` são legíveis e editáveis diretamente pelo usuário; grafo + embeddings são memória semântica/relacional. `MemoryPort` terá duas implementações simultâneas, não uma substituindo a outra.
- **QQ** — API oficial.
- **Workers persistentes vs. on-demand** — persistentes. Máximo ~15 usuários por instância; overhead de manter coroutines vivas é negligível. Flag de configuração seria YAGNI — não implementar.
