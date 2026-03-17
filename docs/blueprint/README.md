# Blueprint - Esqueletos de APIs

Este diretório contém skeletons (esqueletos) de todos os projetos de referência em `/inspiration/`.

## O que são Skeletons?

Skeletons são versões simplificadas do código que preservam apenas:
- ✅ Nomes de funções, classes, módulos
- ✅ Assinaturas e tipos
- ✅ Estrutura de imports e módulos
- ✅ Docstrings e comentários

E removem:
- ❌ Corpo das funções/métodos
- ❌ Implementação detalhada
- ❌ Lógica interna

**Exemplo:**

```rust
// Código original
pub fn process_message(msg: Message) -> Result<Response> {
    let parsed = parse(&msg)?;
    let result = transform(parsed)?;
    Ok(Response::new(result))
}

// Skeleton
pub fn process_message(msg: Message) -> Result<Response>
```

## Projetos Mapeados

| Projeto | Linguagem | Arquivos Skeleton | Descrição |
|---------|-----------|-------------------|-----------|
| **[OpenClaw](openclaw/)** | TypeScript | 150 | Assistente IA pessoal com 22+ canais, 35+ providers, 53+ skills, mobile apps |
| **[nullclaw](nullclaw/)** | Zig | 249 | Sistema de agentes com 17 canais, 50+ providers LLM, 30+ ferramentas |
| **[moltis](moltis/)** | Rust | 480 | Workspace com 42 crates (agentes, canais, providers, tools, memory) |
| **[LobsterAI](LobsterAI/)** | TypeScript | 112 | Electron app com Cowork system, Skills, MCP |
| **[nanobot](nanobot/)** | Python | 67 | Framework de agentes com 13 canais, 8 providers LLM |
| **[ironclaw](ironclaw/)** | Rust | 416 | Sistema de agentes com WASM extensions, MCP, sandbox |

## Estatísticas Gerais

- **Total de arquivos skeleton:** 1,474
- **Linguagens:** Rust (896), Zig (249), TypeScript (262), Python (67)
- **Linhas de código original:** ~1.2M+
- **Linhas de skeleton:** ~60K (95% de redução)

## Estrutura de Cada Projeto

### nullclaw (Zig)
```
nullclaw/
├── README.md
├── EXTRACTION_SUMMARY.md
└── src/
    ├── main_skel.zig           # CLI entry point
    ├── agent_skel.zig          # Agent orchestration
    ├── config_skel.zig         # Configuration types
    ├── channels/               # 17 channel skeletons
    ├── providers/              # 50+ LLM provider skeletons
    ├── tools/                  # 30+ tool skeletons
    ├── security/               # Sandbox, policies, secrets
    └── memory/                 # Memory backends
```

### moltis (Rust)
```
moltis/
├── README.md
├── MIGRATION.md                # Complete crate index
├ apps/
│   └── courier/src/main_skel.rs
└── crates/ (49 crates)
    ├── agents/
    ├── channels/
    ├── providers/
    ├── tools/
    ├── memory/
    └── ... (45 more crates)
```

### LobsterAI (TypeScript)
```
LobsterAI/
├── README.md
├── ARCHITECTURE.md             # IPC architecture
├ SKILLs/                       # Skill implementations
└── src/
    ├── main/                   # Electron main process
    │   ├── main_skel.ts        # Entry point, IPC handlers
    │   ├── libs/
    │   │   └── coworkRunner_skel.ts
    │   └── im/                 # 28 IM channel skeletons
    └── renderer/               # React renderer
        ├── services/           # 14 service skeletons
        ├── store/slices/       # 6 Redux slices
        └── types/              # Type definitions
```

### nanobot (Python)
```
nanobot/
├── README.md
├── CHANNELS.md                 # 13 channels documentation
├ nanobot/
│   ├── agent/                  # Agent logic (16 skeletons)
│   ├── channels/               # 13 channel skeletons
│   ├── providers/              # 8 LLM provider skeletons
│   ├── config/
│   ├── bus/
│   ├── session/
│   └── ...
└── bridge/                     # TypeScript bridge
```

### OpenClaw (TypeScript)
```
openclaw/
├── README.md
├── src/                      # Core engine e gateway
│   ├── entry_skel.ts          # Ponto de entrada
│   ├── index_skel.ts          # Exportações públicas
│   ├── agents/                # Sistema de agentes (ACP)
│   ├── channels/              # Sistema de canais
│   ├── gateway/               # Servidor HTTP/WebSocket
│   ├── providers/             # Auth providers
│   ├── config/                # Sistema de configuração
│   ├── cli/                   # Interface CLI
│   ├── commands/              # Comandos CLI
│   ├── memory/                # Sistema de memória
│   ├── sessions/              # Gerenciamento de sessões
│   ├── browser/               # Automação Playwright
│   └── ... (50+ módulos)
├── extensions/               # Plugins de extensão
│   ├── discord/               # Canal Discord
│   ├── google/                # Provider Google AI
│   ├── diffs/                 # Visualização de diffs
│   ├── openai/                # Provider OpenAI
│   ├── anthropic/             # Provider Anthropic
│   └── ... (72+ extensions)
└── skills/                  # Skills externos CLI
```

### ironclaw (Rust)
```
ironclaw/
├── README.md
└── src/
    ├── lib_skel.rs             # Main library
    ├── app_skel.rs             # Application
    ├── bootstrap_skel.rs       # Bootstrap
    ├── agent/                  # Agent orchestration
    ├── skills/                 # WASM skills system
    ├── tools/                  # MCP tools
    ├── channels/               # Channel integrations
    ├── db/                     # PostgreSQL, libSQL
    ├── llm/                    # LLM providers
    └── ...
```

## Como Usar os Skeletons

### 1. Explorar APIs
Para entender a API pública de um módulo, navegue até o skeleton correspondente:

```bash
# Ver providers do nullclaw
cat docs/blueprint/nullclaw/src/providers/anthropic_skel.zig

# Ver crates do moltis
ls docs/blueprint/moltis/crates/

# Ver canais do nanobot
cat docs/blueprint/nanobot/CHANNELS.md
```

### 2. Entender Arquitetura
Cada projeto tem documentação específica:
- `nullclaw/EXTRACTION_SUMMARY.md` - Detalhes da extração
- `moltis/MIGRATION.md` - Índice completo de crates
- `LobsterAI/ARCHITECTURE.md` - Arquitetura IPC
- `nanobot/CHANNELS.md` - Documentação de canais

### 3. Mapear Funcionalidades
Compare funcionalidades entre projetos:

| Funcionalidade | OpenClaw | nullclaw | moltis | LobsterAI | nanobot | ironclaw |
|---------------|-----------|----------|--------|-----------|---------|----------|
| Agentes | ✅ ACP | ✅ | ✅ | ✅ | ✅ | ✅ |
| Canais (multi) | ✅ (22+) | ✅ (17) | ✅ (10+) | ❌ | ✅ (13) | ✅ |
| Providers LLM | ✅ (35+) | ✅ (50+) | ✅ | ✅ | ✅ (8) | ✅ |
| Tools | ✅ (Skills CLI) | ✅ (30+) | ✅ | ✅ | ✅ | ✅ (MCP) |
| Skills | ✅ (53+ CLI) | ✅ | ✅ | ✅ | ✅ | ✅ (WASM) |
| Memory | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Sandbox | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| MCP | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ |
| Gateway HTTP | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| WebSocket | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Browser | ✅ (Playwright) | ❌ | ✅ | ❌ | ❌ | ✅ |
| Mobile Apps | ✅ (iOS, Android) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Electron | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| TUI | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Hardware | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Túneis | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ |

### 4. Referência de Implementação
Ao implementar uma funcionalidade nova, use os skeletons como referência:

```python
# Implementar novo canal baseado em exemplos existentes
# 1. Ver interface base:
cat nanobot/channels/base_skel.py

# 2. Ver implementação de canal existente (ex: telegram)
cat nanobot/channels/telegram_skel.py

# 3. Comparar com equivalentes em outros projetos
cat nullclaw/src/channels/telegram_skel.zig
```

## Convenções de Nomenclatura

- **Suffixo `_skel.ext`**: Arquivos skeleton (ex: `main_skel.zig`)
- **Arquivos sem suffixo**: Documentação (README.md, MIGRATION.md, etc.)
- **Estrutura de diretórios**: Preserva a organização do projeto original

## Scripts de Extração

Os skeletons foram gerados usando scripts específicos por linguagem:
- **Rust**: Script baseado em parsing de chaves `{ }`
- **Zig**: Script similar ao Rust
- **TypeScript**: Script baseado em regex e análise de sintaxe
- **Python**: Script usando AST do Python

## Notas Importantes

1. **Não é código compilável**: Skeletons são apenas para documentação e referência
2. **Preserva apenas a API pública**: Funções/métodos privados podem não aparecer
3. **Docstrings mantidas**: Comentários de documentação são preservados
4. **Type hints preservados**: Tipos e assinaturas são mantidos intactos

## Próximos Passos

- [x] Mapear todos os 5 projetos de referência
- [x] Criar skeletons para 1,324 arquivos
- [x] Documentar arquitetura de cada projeto
- [ ] Criar guias de migração entre projetos
- [ ] Mapear padrões de design comuns
- [ ] Criar templates de implementação

## Licença

Os skeletons são derivados dos projetos originais em `/inspiration/`. Consulte os respectivos licenses de cada projeto para uso comercial.
