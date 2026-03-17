# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## O que é o Donkey

**Donkey** é um sistema de agentes de IA ("Claw") escrito em Nim, self-hosted em VPS, servindo equipes corporativas pequenas. O projeto está em fase de design arquitetural — nenhuma linha de código do sistema foi escrita ainda.

**Prioridades de design:**
- Arquitetura hexagonal (ports & adapters) — inegociável
- TDD obrigatório — Red-Green-Refactor sem exceções; nunca escrever código antes do teste
- Functional core (`func` Nim), effectful shell (`proc` com Chronos)
- Implementações simples e funcionais primeiro; gaps atacados em iterações posteriores
- Minimal dependencies — o projeto tem aspirações embedded (compila para VPS e potencialmente hardware restrito)
- Providers prioritários (F1): OpenRouter, Zhipu Coding (`https://api.z.ai/api/coding/paas/v4`), OpenCode Zen (gateway multi-protocolo opencode, `opencode/<model-id>`)
- Providers mapeados (F3): OpenRouter, Zhipu, Gemini, Anthropic, MiniMax
- Channels prioritários: Telegram (v1), Discord (v2), depois channels chineses

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
- **OpenRouterAdapter** — injeta `HTTP-Referer` e `X-Title` em todo request (obrigatório pela plataforma)
- **ZhipuAdapter** — traduz `ToolCall` para formato GLM nativo; declara native tools (`web_search`, `code_interpreter`) em `caps()` para que o orchestrator possa delegar ao provider em vez de usar o ToolPort
- **GeminiAdapter** — normaliza histórico antes de enviar: function calls devem vir após model turns, nunca após user turns; converte `functionCall`/`functionResponse` (formato Gemini ≠ OpenAI)
- **AnthropicAdapter** — formato de mensagens próprio (`content` blocks), `tool_use`/`tool_result` blocks distintos do padrão OpenAI
- **MiniMaxAdapter** — API MiniMax (série abab), formato próprio
- **ZenAdapter** — gateway multi-protocolo do opencode CLI. Model IDs: `opencode/<model-id>`. Roteia internamente: modelos OpenAI → `/zen/v1/responses`, modelos Anthropic → `/zen/v1/messages`. Implementado como roteador que despacha para sub-adapters com base URL diferente, não como adapter leaf.

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
INBOUND ADAPTERS
  TelegramAdapter ─┐
  DiscordAdapter  ─┼→ IdentityResolver → SessionManager
  [futuros]       ─┘

APPLICATION LAYER (Chronos, effectful)
  SessionManager → OrchestratorAgent (por sessão)
    ├── MemoryAgent  → MemoryPort  → MdFileAdapter (F1) / PostgresAdapter (F2)
    ├── ToolAgent    → ToolPort    → McpClientAdapter (MCP/Deno subprocess)
    └── [workers]   → ProviderPort → OpenRouterAdapter / ZhipuAdapter / GeminiAdapter

DOMAIN CORE (Nim `func`, zero side effects — testável com mocks puros)
  buildPrompt / planTask / routeMessage / mergeContext
  scoreMemories / rankTools / buildGraphQuery

OUTBOUND ADAPTERS
  ChannelPort → TelegramAdapter / DiscordAdapter / [futuros]
```

Ports são `concept` Nim (structural typing, verificado em compile-time). Adapters não declaram conformidade — o compilador verifica. Mocks para TDD são qualquer tipo que satisfaça o concept.

## Multi-agente

Agentes são actors: cada um tem `AsyncChannel[AgentMessage]` (Chronos) como inbox. Sem estado compartilhado. OrchestratorAgent por sessão ativa; workers spawned on demand, não persistentes.

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

```
data/users/{uuid}/
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

Primeira mensagem de usuário desconhecido dispara onboarding conversacional via Telegram:
1. Donkey se apresenta, pede permissão para fazer perguntas
2. Coleta: nome, como chamar, fuso horário, idioma preferido
3. Cria todos os `.md` do workspace
4. Confirma e oferece ajuda

Ao final: `data/users/{uuid}/` criado com todos os arquivos. Usuário é informado que pode editar `USER.md` diretamente.

## F1 — Escopo da primeira fase

- **Channel:** Telegram (long polling para dev, webhook para produção)
- **Provider:** Zhipu Coding (URL própria, não via OpenRouter) + fallback OpenRouter
- **Memória:** arquivos `.md` — sem Postgreyskull ainda
- **MCP:** client desde o início
- **Bootstrapping:** onboarding conversacional completo
- **Binary:** `donkey` (daemon), `donkey ctl` (CLI de administração)

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
