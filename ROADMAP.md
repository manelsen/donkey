# Donkey — Roadmap

Cada fase termina com algo que roda e é testável. Red-Green-Refactor em tudo.

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

---

## F3 — Multi-provider ✅

**Entregável:** 5 providers funcionando com suas peculiaridades isoladas nos adapters.

- [x] `OpenRouterAdapter`, `AnthropicAdapter`, `GeminiAdapter`, `MiniMaxAdapter`, `ZhipuAdapter`
- [x] Seleção de provider por usuário em `PREFERENCES.md` (inline keyboard `/models`)
- [x] Fallback automático: `buildFallbackFn` + fallback chain por sessão
- [x] `donkey ctl provider test <name>`

---

## F4 — Multi-agente ✅

**Entregável:** orchestrator delega para workers especializados via message passing.

- [x] `AgentMessage` type (amkTask, amkCancel, amkResult, amkError)
- [x] `OrchestratorAgent` + `MemoryAgent` + `ToolAgent` — actors com AsyncQueue inbox
- [x] Cancelamento em cascata via amkCancel
- [x] Native tools Zhipu via `caps()` (web_search, code_interpreter)
- [x] Streaming via OS thread + Channel[string] + partials no globalOutbox

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
- [ ] `.md` como views/exports do grafo (gerados sob demanda) — pós-F6

---

## F7 — Skills Ecosystem ✅

**Entregável:** marketplace Clawhub integrado, skills por usuário.

- [x] `SkillManifest`: nome, versão, script, tools, permissões Deno
- [x] Registry global: `config/skills.toml`; per-user: `data/users/{uuid}/skills/`
- [x] `donkey ctl skill list/install/update`
- [x] User skills mergeadas no orchestrator na criação de sessão

---

## F8 — Channels chineses (parcial)

**Entregável:** WeCom + Feishu funcionais; WeChat e QQ mapeados.

- [x] `WeComAdapter` — Webhook HTTP + API corporativa (corp_id, corp_secret, agent_id)
- [x] `FeishuAdapter` — WebSocket gateway + Lark Open API
- [ ] `WeChatAdapter` — Official Account API (OAuth 2.0, template messages)
- [ ] `QQAdapter` — OneBot protocol

---

## F9 — TUI + Admin

**Entregável:** interface terminal para operação do daemon.

- [ ] TUI com `illwill` ou similar
  - Dashboard: sessões ativas, providers em uso, memória, uptime
  - Log viewer com filtro por usuário/sessão/nível
  - User manager: listar, editar perfil, revogar acesso
- [ ] `donkey ctl` expandido: todos os comandos de F1-F8 consolidados
- [ ] Health check endpoint (Unix socket local — sem HTTP externo)
- [ ] `donkey ctl status` — snapshot do estado do daemon

---

## Decisões abertas (para antes ou durante cada fase)

- [ ] **F1:** Long polling (dev) vs. webhook (produção) — flag de config ou automático?
- [ ] **F2:** Manifesto de skill: TOML embutido no pacote npm ou `clawhub.toml` na raiz?
- [ ] **F4:** Workers persistentes vs. on-demand — revisar após F4 com dados reais de uso
- [ ] **F6:** `.md` como views automáticas (geradas pelo daemon) ou exportadas sob comando?
- [ ] **F8:** QQ — OneBot v11/v12 ou API oficial (se disponível para o caso de uso)?
