# Donkey — Roadmap

Cada fase termina com algo que roda e é testável. Red-Green-Refactor em tudo.

---

## F0 — Scaffolding

**Entregável:** `donkey --version` compila, testa e loga.

- [ ] Projeto nimble: `donkey.nimble`, dependências (Chronos, nimcrypto, parsetoml)
- [ ] Estrutura de diretórios: `src/core/`, `src/ports/`, `src/adapters/`, `src/app/`, `tests/`
- [ ] Logger estruturado (nível, timestamp, contexto) — sem dependência externa
- [ ] Config loader: lê `donkey.toml`, valida campos obrigatórios, falha com mensagem clara
- [ ] `SecretStore` port + `FileSecretAdapter` (nimcrypto ChaCha20-Poly1305 + PBKDF2)
- [ ] `DONKEY_MASTER_KEY` via env; prompt interativo se ausente
- [ ] Suite de testes rodando (`testament` ou `unittest2`)
- [ ] `donkey --version` e `donkey --help`

---

## F1 — Primeiro agente funcional

**Entregável:** conversa real no Telegram com memória em `.md` e onboarding.

### Domain core (`src/core/` — só `func`)
- [ ] Tipos base: `Message`, `Role`, `ConversationHistory`, `UserId`, `SessionId`
- [ ] `CompletionRequest`, `CompletionResponse`, `Token` (streaming)
- [ ] `AgentConfig`, `UserProfile`, `UserPreferences`
- [ ] `buildPrompt/3`, `mergeHistory/2`, `shouldBootstrap/1`
- [ ] `parseBootstrapResponse/1` — extrai nome/timezone/idioma da resposta do LLM

### Ports (`src/ports/`)
- [ ] `ProviderPort` concept: `complete`, `stream`, `caps`
- [ ] `ChannelPort` concept: `receive`, `send`, `ack`
- [ ] `MemoryPort` concept: `loadUser`, `saveUser`, `appendMemory`, `readContext`
- [ ] `SecretStore` concept (já do F0, formalizar aqui)

### Adapters
- [ ] `ZhipuAdapter` → `https://api.z.ai/api/coding/paas/v4`
  - Traduz `ToolCall` para formato GLM
  - Declara native tools (`web_search`, `code_interpreter`) em `caps()`
- [ ] `TelegramAdapter` — long polling
  - Recebe updates, envia mensagens, suporte a Markdown
  - `IdentityResolver`: `telegram_user_id → UserId` (cria UUID na primeira vez)
- [ ] `MdFileAdapter` — lê/escreve workspace do usuário
  - Cria estrutura `data/users/{uuid}/` com todos os `.md` na primeira vez
  - Lê USER.md, PREFERENCES.md, MEMORY.md como contexto
  - Atualiza MEMORY.md após cada sessão

### Aplicação
- [ ] `SessionManager`: cria/recupera sessão por usuário
- [ ] `AgentRunner`: loop principal (single agent, sem workers ainda)
  - Recebe mensagem → carrega contexto → chama provider → atualiza memória → responde
- [ ] Bootstrapping: detecta workspace ausente → dispara onboarding conversacional
  - Coleta nome, como chamar, timezone, idioma
  - Cria todos os `.md` ao final

### CLI
- [ ] `donkey start` — inicia daemon
- [ ] `donkey ctl user list` — lista usuários registrados
- [ ] `donkey ctl user show <uuid>` — exibe perfil

---

## F2 — MCP + Tools

**Entregável:** agente executa ferramentas via MCP e skills Clawhub.

- [ ] `ToolPort` concept: `invoke`, `listTools`, `toolSchema`
- [ ] `McpClientAdapter` — cliente JSON-RPC sobre stdio
  - Gerencia ciclo de vida do processo filho
  - `initialize` handshake, `tools/list`, `tools/call`
  - Timeout e cancelamento via Chronos
- [ ] `DenoSkillAdapter` — especialização do McpClientAdapter para subprocessos Deno
  - Sandbox via `--allow-*` declarado no manifesto da skill
- [ ] Integração no `AgentRunner`: detecta tool calls na resposta → executa → devolve resultado
- [ ] `donkey ctl tool install <mcp-server-cmd>` — registra MCP server
- [ ] `donkey ctl skill install <clawhub-name>` — instala via `npx clawhub@latest install`
- [ ] Listagem de tools disponíveis injetada no system prompt

---

## F3 — Multi-provider

**Entregável:** 5 providers funcionando com suas peculiaridades isoladas nos adapters.

- [ ] `ProviderCaps` completo: streaming, toolCalling, nativeTools, maxContextTokens, requiresUserTurnBeforeAssistantTool
- [ ] `OpenRouterAdapter` — injeta `HTTP-Referer` e `X-Title` em todo request
- [ ] `AnthropicAdapter` — formato de messages próprio, tool_use/tool_result blocks
- [ ] `MiniMaxAdapter` — API MiniMax (abab series), formato próprio
- [ ] `GeminiAdapter` — normaliza turn ordering; traduz `functionCall`/`functionResponse`
- [ ] Seleção de provider por usuário em `PREFERENCES.md`
- [ ] Fallback: se provider primário falha, tenta próximo da lista
- [ ] `donkey ctl provider test <name>` — verifica conectividade e API key

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
