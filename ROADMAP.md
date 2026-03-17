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
  - Gerencia ciclo de vida do processo filho (osproc)
  - `initialize` handshake, `tools/list`, `tools/call`
  - Helpers puros exportados e testados: `buildRequest`, `parseToolSchema`, `parseToolResult`
- [ ] `DenoSkillAdapter` — especialização do McpClientAdapter para subprocessos Deno
  - Sandbox via `--allow-*` declarado no manifesto da skill
- [ ] Integração no `AgentRunner`: detecta tool calls na resposta → executa → devolve resultado
- [ ] `donkey ctl tool install <mcp-server-cmd>` — registra MCP server
- [ ] `donkey ctl skill install <clawhub-name>` — instala via `npx clawhub@latest install`
- [ ] Listagem de tools disponíveis injetada no system prompt

**Testes:** t_mcp_client — buildRequest, parseToolSchema, parseToolResult, tipos.

---

## F3 — Multi-provider ✅

**Entregável:** 5 providers funcionando com suas peculiaridades isoladas nos adapters.

- [x] `OpenRouterAdapter` — injeta `HTTP-Referer` e `X-Title` em todo request (obrigatório)
- [x] `AnthropicAdapter` — `system` top-level, `x-api-key` auth, `anthropic-version` header
- [x] `GeminiAdapter` — role "model", `systemInstruction`, auth via query param `key=`
- [x] `MiniMaxAdapter` — `sender_type USER/BOT`, `text` field, `bot_setting` para system
- [ ] Seleção de provider por usuário em `PREFERENCES.md`
- [ ] Fallback: se provider primário falha, tenta próximo da lista
- [ ] `donkey ctl provider test <name>` — verifica conectividade e API key

**Testes:** t_openrouter, t_anthropic, t_gemini, t_minimax — caps, buildBody, parseResponse.

---

## F4 — Multi-agente

**Entregável:** orchestrator delega para workers especializados via message passing.

- [ ] `AgentMessage` type (variant: task, result, cancel, error)
- [ ] `AgentId` e `AgentRef` (handle para inbox Chronos)
- [ ] `OrchestratorAgent` refatorado: planeja e delega, não executa diretamente
- [ ] `MemoryAgent`: especializado em recuperação e persistência de contexto
- [ ] `ToolAgent`: especializado em execução de MCP/skills
- [ ] Cancelamento em cascata: encerrar sessão cancela todos os workers filhos
- [ ] Native tools Zhipu: orchestrator decide entre ToolAgent vs. delegar ao provider por `caps()`

---

## F5 — Discord + Cross-channel

**Entregável:** usuário continua conversa do Telegram no Discord sem perder contexto.

- [ ] `DiscordAdapter` — gateway WebSocket, slash commands, embeds
- [ ] `IdentityResolver` generalizado: `(ChannelType, channel_user_id) → UserId`
- [ ] `SessionManager` multi-canal: sessão tem `seq[ActiveChannel]`
- [ ] `/continue` command em qualquer canal — reanexar sessão ativa
- [ ] `SessionChannel` tracking no workspace (qual canal está ativo)
- [ ] `donkey ctl session list <user>` — exibe sessões e canais ativos

---

## F6 — Postgreyskull

**Entregável:** memória semântica e relacional substituindo os `.md` como backend.

- [ ] Setup PostgreSQL + pgvector + Apache AGE
- [ ] Schema do grafo (nodes: Person, Fact, Solution, ErrorPattern, Concept, Memory, Session; edges conforme doc)
- [ ] `PostgresMemoryAdapter` implementando `MemoryPort`
  - `storeNode`, `storeEdge`, `vectorSearch`, `graphTraverse`, `hybridSearch`
- [ ] Pipeline de embedding: texto → `qwen3-embedding-8b` (OpenRouter) → vetor
- [ ] Migração: importa `.md` existentes para o grafo na primeira vez
- [ ] `.md` passam a ser exports/views do grafo (gerados sob demanda)
- [ ] `donkey ctl memory search <user> "<query>"` — busca híbrida manual

---

## F7 — Skills Ecosystem

**Entregável:** marketplace Clawhub integrado, skills por usuário.

- [ ] `SkillManifest`: nome, versão, permissões Deno, descrição, tools expostas
- [ ] Registry local: `config/skills.toml` com skills instaladas globalmente
- [ ] Per-user override: `data/users/{uuid}/skills/` com versões ou configs locais
- [ ] `donkey ctl skill list` — skills instaladas + tools que expõem
- [ ] `donkey ctl skill update` — atualiza todas via Clawhub
- [ ] Versionamento: `clawhub@1.2.3` fixado por usuário se necessário

---

## F8 — Channels chineses

**Entregável:** WeCom funcional; WeChat e QQ mapeados.

- [ ] `WeComAdapter` — Webhook + API corporativa (autenticação mais simples)
  - Token validation, message receive/send, media
- [ ] `WeChatAdapter` — Official Account API
  - OAuth 2.0, menu, template messages
- [ ] `QQAdapter` — OneBot protocol (escolher implementação)
- [ ] Documentação de autenticação por channel (cada um tem seu fluxo)

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
