# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## O que é o Donkey

**Donkey** é um sistema de agentes de IA ("Claw") escrito em Nim, self-hosted em VPS, servindo equipes corporativas pequenas. O projeto tem ~30k LOC em 149 arquivos Nim com 120 arquivos de teste, seguindo rigorosamente arquitetura hexagonal e TDD.

**Estado atual (branch ralph/donkey-v1-sovereign-pipeops):**
- Channels implementados: Telegram ✓, Discord ✓, WeCom ✓ — outros mapeados (F2+)
- Providers implementados: OpenAI ✓, Anthropic ✓, OpenRouter ✓, Zhipu ✓, Gemini ✓, MiniMax ✓, DeepSeek ✓, Ollama ✓
- Memória F1 (MdFile) ✓, Postgreyskull F2+ em andamento
- Orchestrator multi-turn ✓, tool loop ✓, onboarding de 12 fases ✓
- ZenAdapter (opencode gateway) — planejado, não implementado ainda

**Princípios inegociáveis:**
- Arquitetura hexagonal (ports & adapters)
- TDD obrigatório — Red-Green-Refactor sem exceções; nunca escrever código antes do teste
- Functional core (`func` Nim), effectful shell (`proc` com Chronos)
- Implementações simples e funcionais primeiro; gaps atacados em iterações posteriores
- Minimal dependencies — o projeto tem aspirações embedded (compila para VPS e potencialmente hardware restrito)

## Estilo de código

### Result[T, E] + pipeline operators — obrigatório em todo I/O

Exceções (`raise`/`try`) são proibidas em adapters e na camada de aplicação. Todo I/O fallível retorna `Result[T, string]`. O código de chamada decide o que fazer com o erro — o adapter só reporta.

```nim
import donkey/core/pipeops   # exporta results + |> e >>=

# Adapter retorna Result — nunca lança exceção
proc complete*(a: ZhipuAdapter; req: CompletionRequest): Result[CompletionResponse, string] =
  try:
    # ... HTTP call ...
    ok(CompletionResponse(...))
  except CatchableError as e:
    err(e.msg)

# ? propaga o erro para cima (igual ao ? do Rust)
proc runTurn*(runner: var AgentRunner; ...): Result[string, string] =
  let resp = ? runner.provider.complete(req)   # retorna Err se falhar
  ok(resp.text)

# No loop principal: valueOr e isOkOr para terminação local
let msgs = channel.receive().valueOr:
  log.error("receive: " & error)
  continue

channel.send(outMsg).isOkOr: log.error("send: " & error)

# |> para transformações puras encadeadas
let context = (ctx.memoryMd & "\n" & ctx.preferencesMd) |> strip

# >>= para encadear steps fallíveis (railway-oriented)
provider.complete(req) >>= saveToMemory >>= notifyUser
```

**Regras:**
- `try/except` apenas dentro do adapter, nunca exposto para fora
- Procs do domínio (`func`) continuam puros — sem Result, sem I/O
- `pipeops.nim` é o único lugar onde `results` é importado diretamente; o resto importa via `pipeops`

## Decisões arquiteturais tomadas

### Linguagem e concorrência
- **Nim** para tudo
- **Chronos** (não asyncdispatch) para I/O assíncrono — cancelamento nativo, error propagation correto, structured concurrency
- Threadpool Nim para trabalho CPU-bound (embeddings, processamento de grafo)

### Skills e MCP — ToolPort unificado
Skills Clawhub (pacotes npm) e MCP servers são tratados identicamente: processos com comunicação JSON-RPC via stdin/stdout. Um único `ToolPort` com `McpClientAdapter` cobre ambos. Skills rodam como subprocessos **Deno** (sandbox nativo `--allow-*`, compatibilidade npm, TypeScript nativo).

```
ToolPort → McpClientAdapter → [MCP server process]
                            → [Deno skill process]  ← Clawhub / custom
```

MCP é prioritário desde o primeiro dia.

### Memória — duas fases

**F1 (v1):** memória em arquivos `.md` no workspace do usuário. O agente lê e atualiza diretamente. Simples, hackável, sem banco.

**F2+:** **Postgreyskull** — PostgreSQL com:
- **pgvector** — embeddings via `qwen3-embedding-8b` (OpenRouter), vetores de 4096 dimensões
- **Apache AGE** — grafo de conhecimento pessoal com Cypher queries
- Busca híbrida: vetorial (semântica) + traversal de grafo (relacional) combinados

### Providers — arquitetura

Cada adapter absorve os próprios quirks. O `ProviderPort` fica limpo:

```nim
type ProviderPort* = concept p
  p.complete(CompletionRequest) is Future[CompletionResponse]
  p.stream(CompletionRequest)   is AsyncIter[Token]
  p.caps()                      is ProviderCaps

type ProviderCaps* = object
  streaming:        bool
  toolCalling:      bool
  nativeTools:      seq[NativeTool]  # provider executa internamente (ex: Zhipu web_search)
  maxContextTokens: int
```

Quirks conhecidos por adapter:
- **OpenRouterAdapter** — injeta `HTTP-Referer` e `X-Title` em todo request (obrigatório pela plataforma); suporta model catalog live com cache TTL
- **ZhipuAdapter** — traduz `ToolCall` para formato GLM nativo; declara native tools (`web_search`, `code_interpreter`) em `caps()` para que o orchestrator possa delegar ao provider em vez de usar o ToolPort
- **GeminiAdapter** — normaliza histórico antes de enviar: function calls devem vir após model turns, nunca após user turns; converte `functionCall`/`functionResponse` (formato Gemini ≠ OpenAI)
- **AnthropicAdapter** — formato de mensagens próprio (`content` blocks), `tool_use`/`tool_result` blocks distintos do padrão OpenAI
- **MiniMaxAdapter** — API MiniMax (série abab), formato próprio
- **DeepSeekAdapter** — OpenAI-compatible com quirks de reasoning tokens
- **OllamaAdapter** — instância local; sem streaming nativo, polling de resposta
- **ZenAdapter** — PLANEJADO (F2+): gateway multi-protocolo do opencode CLI. Model IDs: `opencode/<model-id>`. Roteará: OpenAI → `/zen/v1/responses`, Anthropic → `/zen/v1/messages`. Não implementado ainda.

Sem adapter genérico compartilhado — cada um tem o seu. OpenCode Zen é gateway curado (gratuitos disponíveis, zero markup), não OpenAI-compatible universal.

### Secrets — nimcrypto (pure Nim, zero deps C)

`nimcrypto`: ChaCha20-Poly1305 + PBKDF2-SHA256. Sem `age` externo, sem GPG.

Formato do arquivo: `[salt 32B][nonce 12B][ciphertext][tag 16B]` — binário puro.

`DONKEY_MASTER_KEY` no ambiente (ou prompt interativo na inicialização) → decrypt em memória → `SecretString` (zeroed destructor). Disco nunca vê plaintext. Interface `SecretStore` como port para futuros backends.

### Config
**TOML** para toda configuração. Sem YAML.

### Interface
**CLI + TUI**. Sem web UI.

## Arquitetura hexagonal

```
INBOUND ADAPTERS (adapters/channel/)
  TelegramAdapter ─┐
  DiscordAdapter  ─┼→ IdentityResolver → SessionManager
  WeComAdapter    ─┤
  [13 canais]     ─┘

APPLICATION LAYER (app/ — Chronos, effectful)
  SessionManager → OrchestratorAgent (por sessão, AsyncQueue[AgentMessage] como inbox)
    ├── MemoryAgent  → MemoryPort  → MdFileAdapter (F1) / PostgresAdapter (F2+)
    ├── ToolAgent    → ToolPort    → McpClientAdapter (MCP/Deno subprocess)
    └── NativeTools  → ProviderPort → OpenRouterAdapter / ZhipuAdapter / [8 providers]

DOMAIN LAYER (domain/ — Nim `func`, zero side effects, 100% testável)
  ├── message.nim       → ChatMessage, CompletionRequest/Response, ToolCall
  ├── identity.nim      → UserId, link codes, cross-channel mapping
  ├── personality.nim   → PersonalityTraits, onboarding phases (12)
  ├── channels/         → formatadores puros por canal (telegram_pure, discord_pure, …)
  ├── providers/        → tradutores puros por provider (openai_pure, anthropic_pure, …)
  ├── memory/           → chunking, decay, graph_pure, rrf (algoritmos puros)
  └── routing/          → smart_route, failover

CORE INFRASTRUCTURE (core/ — sem I/O externo)
  Log, Cron, Actor, Pipeops, Types, CommandRouting, Onboarding,
  ToolLoop, NativeToolDispatch, SecretScan, SessionIngress, Debounce

OUTBOUND ADAPTERS (adapters/channel/)
  ChannelPort → TelegramAdapter / DiscordAdapter / WeComAdapter / [futuros]
```

Ports são `concept` Nim (structural typing, verificado em compile-time). Adapters não declaram conformidade — o compilador verifica. Mocks para TDD são qualquer tipo que satisfaça o concept.

**Camadas estruturais do source:**
```
src/donkey/
  core/       ← infra pura, zero I/O externo (types, log, cron, actors, pipeops)
  domain/     ← lógica de negócio pura (func only), zero side effects
  ports/      ← concepts Nim (ChannelPort, ProviderPort, MemoryPort, ToolPort, …)
  app/        ← shell de casos de uso: lifecycle, actors, queues, wiring (Chronos)
  adapters/   ← I/O boundary: channel, provider, memory, tool, http, secrets, ipc
  infra/      ← sandbox: Docker, WASM, limits, paddock layout
  config/     ← DonkeyConfig, loader TOML, skills/clawhub registry
  tui/        ← dashboard terminal
```

## Boundary Rules

Estas regras agora são enforced por `scripts/check_boundaries.sh` e `tests/architecture/t_boundaries.nim`.

- `core` só contém tipos, parsers, reducers, deciders e helpers puros
- `core` não importa `adapters/*`, `chronos`, `chronos/asyncsync`, `osproc`, `httpclient` nem `parsetoml`
- `ports` definem capacidades estáveis; não importam `adapters/*` nem `app/*`
- `app` é shell de casos de uso: lifecycle, actors, queues, streaming, polling, wiring
- `adapters` traduzem I/O externo para `ports`; não carregam semântica cross-channel ou decisão de negócio

Checklist de refactor/PR:
- isso é `core` ou `shell`?
- isso depende de `port` ou de adapter concreto?
- isso deveria ser uma decisão pura testável?

## Multi-agente

Agentes são actors: cada um tem `AsyncQueue[AgentMessage]` (Chronos) como inbox. Sem estado compartilhado. OrchestratorAgent por sessão ativa; workers spawned on demand, não persistentes.

Native tools do Zhipu: quando disponíveis (`caps().nativeTools`), o orchestrator pode delegar diretamente ao provider em vez de despachar para o ToolAgent — mais rápido e mais barato para web search.

## Identidade e sessões cross-channel

Sessões pertencem ao **usuário** (UUID interno), não ao canal. Canal é entrada/saída intercambiável. `/continue` em qualquer canal reanexar o usuário à sessão ativa — contexto preservado.

Mapeamento: `(channel_type, channel_user_id) → user UUID`.

## Grafo de conhecimento pessoal (F2+)

**Nós** — todos têm `id`, `user_id`, `embedding vector(4096)`, `created_at`, `confidence`:
`Person`, `Fact`, `Preference`, `Solution`, `ErrorPattern`, `Concept`, `Document`, `Task`, `Memory`, `Session`

**Arestas principais:**
```
(Person)-[:IS_CHILD_OF|IS_PARENT_OF|KNOWS]->(Person)
(Fact)-[:ABOUT]->(Person|Concept)
(Solution)-[:RESOLVES]->(ErrorPattern)
(Solution)-[:USES]->(Concept)
(Memory)-[:MENTIONS]->(Person|Concept|Task)
(Memory)-[:FROM]->(Session)
(Session)-[:CONTINUED_IN]->(Session)   ← cross-channel continuity
(User)-[:HAS_PREFERENCE]->(Preference)
```

## Workspace por usuário

Os `.md` são vistas legíveis do conhecimento do agente sobre o usuário. Editáveis diretamente — o agente relê na próxima conversa. Em F2+ ficam sincronizados com o grafo.

O caminho dos paddocks é configurável via `donkey.toml` (`paddocks = "~/.donkey/paddocks"`), padrão `{home}/paddocks/`.

```
{paddocks}/{uuid}/
  USER.md             ← perfil do usuário (padrão OpenClaw, com frontmatter)
  PREFERENCES.md      ← preferências (idioma, provider, estilo)
  MEMORY.md           ← índice de memórias
  CONTACTS.md         ← pessoas e relações
  SOLUTIONS.md        ← soluções técnicas indexadas por problema
  sessions/{id}.md    ← resumo por sessão (gerado ao fechar)
  attachments/
  skills/             ← overrides de skills por usuário
  .secrets/
    secrets.toml.age  ← API keys pessoais (nimcrypto)
config/
  donkey.toml         ← configuração global
  secrets.enc         ← secrets globais (nimcrypto)
```

**Padrão USER.md** (adotado do OpenClaw):
```markdown
---
summary: "User profile record"
read_when:
  - Bootstrapping a workspace
  - Starting any conversation
---

# USER.md — About Your Human

- **Name:**
- **What to call them:**
- **Pronouns:** _(optional)_
- **Timezone:**
- **Language:**
- **Notes:**

## Context

_(O que importa para eles? O que estão construindo? O que os frustra? Construir ao longo do tempo.)_

---

The more you know, the better you can help. But remember — you're learning about a person, not building a dossier. Respect the difference.
```

## Bootstrapping (F1 — onboarding de novo usuário)

Primeira mensagem de usuário desconhecido dispara onboarding conversacional. A state machine (`core/onboarding/onboarding.nim` + `domain/personality.nim`) tem 12 fases:

```
WakeUp → ModeChoice → (Guided | Free) →
  DimensionChoice → NameChoice →
  UserName → Timezone → Language → Done
```

Em modo Guided, o Donkey coleta dimensões de personalidade uma a uma. Em modo Free, pula direto para coleta de identidade. Ao final, `{paddocks}/{uuid}/` é criado com todos os arquivos e o usuário é informado que pode editar `USER.md` diretamente.

## F1 — Escopo da primeira fase (em produção)

- **Channels:** Telegram ✓ (long polling para dev, webhook para produção), Discord ✓, WeCom ✓
- **Providers:** todos 8 implementados; prioritários são Zhipu Coding e OpenRouter
- **Memória:** arquivos `.md` no paddock do usuário ✓ — Postgreyskull é F2+
- **MCP:** client desde o início ✓
- **Bootstrapping:** onboarding de 12 fases ✓
- **Native tools:** shell, web_fetch, web_search, calc, fs (read/write/find/grep), git ✓
- **Sandbox:** Docker e WASM disponíveis para execução de código (infra/sandbox/)
- **Binary:** `donkey` (daemon), `donkey ctl` (CLI de administração)
- **Model catalog:** descoberta dinâmica de modelos via OpenRouter, Groq, Anthropic, Gemini e models.dev (com cache TTL)

**Ainda não implementado (F2+):**
- ZenAdapter (opencode gateway, `opencode/<model-id>`)
- Postgreyskull (pgvector + Apache AGE)
- Channels adicionais: QQ, Feishu, Slack, Signal, DingTalk, Matrix, Email, WhatsApp (adapters planejados)

## Material de referência (`docs/`)

```
docs/blueprint/          ← esqueletos de 6 claws de referência
  README.md              ← tabela comparativa de features
  ironclaw/              ← Rust: WASM skills, MCP, sandbox
  moltis/                ← Rust: workspace 49 crates, gateway separado
  nullclaw/              ← Zig: 29 canais, 50+ tools, sandbox avançado
  openclaw/              ← TypeScript: plugin architecture, Clawhub, USER.md pattern
  LobsterAI/             ← TypeScript/Electron: IPC tipado, Cowork runner
  nanobot/               ← Python: message bus, config simples
docs/nim/                ← stdlib Nim, manual, tutoriais
inspiration/             ← projetos-fonte originais
```

## Processo de trabalho

1. Fechar decisões arquiteturais abertas
2. Traçar roadmap detalhado por fase
3. Implementar em Red-Green-Refactor estrito — teste antes, código depois
4. Simples e funcional primeiro; refinar em iterações posteriores
