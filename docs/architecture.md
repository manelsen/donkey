# Arquitetura — Donkey

Donkey é um sistema de agentes de IA self-hosted escrito em Nim. Arquitetura hexagonal estrita: domínio puro no centro, ports como contracts, adapters nas bordas. Zero dependência do domínio para com infrastructure.

---

## Visão geral

```
┌─────────────────────────────────────────────────────────────────┐
│  INBOUND ADAPTERS                                                │
│  TelegramAdapter ─┐                                             │
│  DiscordAdapter  ─┼──▶  IdentityResolver ──▶ SessionManager    │
│  WeComAdapter    ─┘                               │             │
└───────────────────────────────────────────────────┼─────────────┘
                                                    │
┌───────────────────────────────────────────────────▼─────────────┐
│  APPLICATION LAYER  (Chronos, effectful)                        │
│                                                                  │
│  SessionManager ──▶ OrchestratorAgent (por sessão ativa)        │
│                          │                                       │
│                    ┌─────┼──────────────────────┐               │
│                    │     │                      │               │
│               MemoryAgent  ToolAgent         [workers]          │
│                    │         │                  │               │
│               MemoryPort  ToolPort          ProviderPort        │
└───────────────────────────────────────────────────┬─────────────┘
                                                    │
┌───────────────────────────────────────────────────▼─────────────┐
│  DOMAIN CORE  (Nim `func`, zero side effects)                   │
│                                                                  │
│  buildPrompt · trimTo · needsOnboarding                         │
│  parseOnboardingResponse · routeMessage                         │
│  buildGraphQuery · scoreMemories · rankTools                    │
└─────────────────────────────────────────────────────────────────┘
                                                    │
┌───────────────────────────────────────────────────▼─────────────┐
│  OUTBOUND ADAPTERS                                               │
│                                                                  │
│  ProviderPort → ZhipuAdapter · OpenRouterAdapter                │
│               → AnthropicAdapter · GeminiAdapter · MiniMaxAdapter│
│                                                                  │
│  ToolPort    → McpClientAdapter (MCP servers + Deno skills)     │
│                                                                  │
│  MemoryPort  → MdFileAdapter (F1) · PostgresAdapter (F2+)       │
│                                                                  │
│  ChannelPort → TelegramAdapter · DiscordAdapter · WeComAdapter  │
│                                                                  │
│  HttpPort    → StdHttpAdapter (VPS) · ChronosHttpAdapter (IoT)  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Ports (concepts Nim — structural typing, verificado em compile-time)

| Port | Assinatura | Adapters |
|------|-----------|---------|
| `ProviderPort` | `complete(CompletionRequest) → Result[CompletionResponse, string]` + `caps()` | Zhipu, OpenRouter, Anthropic, Gemini, MiniMax |
| `ChannelPort` | `receive() → Result[seq[InboundMessage], string]` + `send(OutboundMessage)` + `ack(string)` | Telegram, Discord, WeCom, Feishu |
| `ToolPort` | `listTools() → Result[seq[ToolSchema], string]` + `invoke(ToolCall) → Result[ToolResult, string]` | `McpClientAdapter` |
| `MemoryPort` | `hasProfile` + `loadContext` + `saveUserMd` + `appendMemory` + `savePreferences` | `MdFileAdapter`, `PostgresAdapter` |
| `HttpPort` | `get(url, headers) → Result[HttpResponse, string]` + `post(url, body, headers)` | `StdHttpAdapter`, `ChronosHttpAdapter` |
| `SecretStore` | `get(key) → Result[string, string]` + `set(key, value)` + `delete(key)` | `FileKeyStore` |

Adapters não declaram conformidade — o compilador verifica o concept no ponto de uso. Mocks para TDD são qualquer tipo que satisfaça o concept.

---

## Camada HTTP interna

`HttpPort` é um port **interno** (adapters → HttpPort), não exposto para a camada de aplicação. Permite trocar o backend TLS sem tocar em nenhum adapter:

```
ZhipuAdapter ──┐
OpenRouterAdapter ─┤
AnthropicAdapter ──┼──▶ http: StdHttpAdapter    (VPS — std/httpclient + OpenSSL)
GeminiAdapter ─────┤               ↕
MiniMaxAdapter ────┤       ChronosHttpAdapter   (IoT — Chronos + bearssl, zero C deps)
TelegramAdapter ───┘
```

**Adapter atual:** `StdHttpAdapter` — stateless, criado pelo construtor de cada adapter via `newStdHttpAdapter()`.

---

## Multi-agente — modelo de actors

Agentes são actors: cada um tem `AsyncQueue[AgentMessage]` (Chronos) como inbox. Sem estado compartilhado.

```
OrchestratorAgent (por sessão)
  │  recebe: amkTask (mensagem do usuário)
  │  envia:  amkTask → MemoryAgent, ToolAgent, workers
  │  aguarda: amkResult / amkError
  │
  ├── MemoryAgent   (AsyncQueue inbox)
  │     recebe amkTask → carrega/salva contexto → amkResult
  │
  ├── ToolAgent     (AsyncQueue inbox)
  │     recebe amkTask → executa tool call → amkResult
  │
  └── [workers]    (AsyncQueue inbox)
        recebe amkTask → chama provider → amkResult
        spawned on-demand, não persistentes
```

Cancelamento em cascata: `amkCancel` propagado para todos os workers da sessão via `cancelSoon()`.

---

## Function calling — pipeline

```
1. buildSystemPrompt()   → lista tools como JSON schema no system prompt (fallback legível)
2. buildBody()           → serializa req.tools como array OpenAI function calling format
3. provider.complete()   → retorna CompletionResponse com toolCalls: seq[ToolCallRequest]
4. addAssistantWithToolCalls(text, calls) → registra turn no histórico
5. for each toolCall:    → despacha para ToolAgent ou executeNativeTool
6. addToolResult(id, result) → adiciona tool result ao histórico
7. repetição detectada?  → aborta se (tool, args) visto ≥ 2 vezes seguidas
8. hard cap: 50 rounds
9. após loop: progress embed fecha com isPartial=false, contagem total
```

### Quirks por adapter

- **OpenRouter/Zhipu**: `tools[]` com `type:function`, `tool_choice:"auto"`; resposta com `tool_calls[{id,type,function:{name,arguments}}]`
- **Anthropic**: `tool_use`/`tool_result` content blocks (não implementado ainda)
- **Gemini**: `functionCall`/`functionResponse`; `requiresUserFirst` — function response deve seguir model turn

---

## Sandbox — bash tool

O bash tool (`executeNativeTool` com nome `bash`) isola execução dentro do paddock do usuário.

```
~/.donkey/paddocks/{uuid}/    ← workdir + limite de filesystem
```

Modos de sandbox configurados em `donkey.toml`:

| Modo | `[sandbox] mode =` | Isolamento | Requisito |
|------|-------------------|-----------|-----------|
| `smNone` | `"none"` (default) | Só CWD — sem restrição de paths absolutos | Nenhum |
| `smDocker` | `"docker"` | Container efêmero; bind mount paddock em `/workspace` | Docker daemon |

`resolveInPaddock` colapsa `..` sem syscall; `inPaddock` verifica prefix. Paths fora do paddock são rejeitados antes de executar. Symlinks ignorados em `find`/`grep` (não seguidos).

**Startup log:** `sandboxLogLevel` emite warning se `smNone` (sem sandbox real), info se `smDocker`.

---

## Memória — duas fases

**F1:** arquivos `.md` no workspace do usuário (`MdFileAdapter`). Agente lê e atualiza diretamente. Hackável, sem banco de dados.

**F2+:** **Postgreyskull** — PostgreSQL com:
- **pgvector** — embeddings Qwen3-Embedding-8B (4096 dim), busca cosine similarity
- **Apache AGE** — grafo de conhecimento pessoal com Cypher queries
- Busca híbrida: vetorial (semântica) + traversal de grafo (relacional)

---

## Workspace por usuário

```
data/users/{uuid}/
  USER.md             ← perfil (padrão OpenClaw + frontmatter)
  PREFERENCES.md      ← idioma, provider, estilo
  MEMORY.md           ← índice de memórias
  CONTACTS.md         ← pessoas e relações
  SOLUTIONS.md        ← soluções por problema
  sessions/{id}.md    ← resumo por sessão
  skills/             ← overrides de skills
  .secrets/
    secrets.toml.enc  ← API keys pessoais (nimcrypto AES-256-GCM)
config/
  donkey.toml         ← config global
  secrets.enc         ← secrets globais
```

---

## Identidade cross-channel

Sessões pertencem ao **usuário** (UUID interno), não ao canal. Canal é I/O intercambiável.

```
(channel_type, channel_user_id) → user UUID
```

`/continue` em qualquer canal reanexar à sessão ativa — contexto preservado.

---

## Concorrência

- **Chronos** (não `asyncdispatch`): cancelamento nativo, error propagation correto, structured concurrency
- **Nim threadpool**: trabalho CPU-bound (embeddings, grafo)
- **AsyncQueue[AgentMessage]**: inbox por actor, sem estado compartilhado

---

## Deployment

**Systemd --user service** — sem root, roda como o próprio usuário:

```bash
donkey service install    # copia binary, escreve unit file, injeta keys do env atual
donkey service start      # systemctl --user start donkey
donkey service logs -f    # journalctl --user -u donkey -f
donkey service logs --cat # saída limpa (só mensagem, sem metadata do journal)
donkey service restart
donkey service stop
donkey service remove     # desregistra; config e dados preservados
```

Arquivos:
- Unit: `~/.config/systemd/user/donkey.service`
- Env/secrets: `~/.config/donkey/donkey.env` (chmod 600)
- Config: `~/.config/donkey/donkey.toml`
- Binary: `~/.local/bin/donkey`
- Dados: `~/.donkey/` (DONKEY_HOME)

`deploy/install.sh` é um script standalone equivalente para quem preferir não usar `donkey service install`.

Para iniciar automaticamente no boot sem login:
```bash
loginctl enable-linger $USER
```

## Layout de código

```
src/donkey/
  core/              ← tipos base, logger, pipeops (Result + |> + >>=)
  domain/            ← lógica pura (func), sem I/O
  config/            ← types.nim (DonkeyConfig, SandboxMode) + loader.nim
  ports/             ← concepts (interfaces)
  adapters/
    provider/        ← zhipu, openrouter, anthropic, gemini, minimax
    channel/         ← telegram, discord, wecom, feishu
    memory/          ← md_file, postgres
    http/            ← std_http, (chronos_http — a implementar)
    tool/            ← mcp_client, deno_skill
    ipc/             ← unix socket client
    embedding/       ← openrouter_embed
  app/               ← orchestrator, session_manager, native_tools, sandbox, ipc_server
tests/
  core/ · domain/ · config/ · provider/ · app/
```
