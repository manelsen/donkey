# OpenClaw - Skeletons

Este diretório contém skeletons (esqueletos) do projeto **OpenClaw** - um assistente de IA pessoal extensível.

## O que é OpenClaw?

OpenClaw é um assistente de IA pessoal que roda em seus próprios dispositivos, integrando com múltiplos canais de comunicação (WhatsApp, Telegram, Slack, Discord, Signal, iMessage, etc.) e fornecendo uma arquitetura extensível para adicionar novos canais, providers de modelos e skills.

## 📊 Estatísticas

| Módulo | Arquivos Skeleton | Descrição |
|---------|------------------|-----------|
| **src/** | 100 | Código fonte principal (gateway, agents, channels, etc.) |
| **extensions/** | 50 | Plugins de extensão (canais, providers) |
| **skills/** | 0 | Skills externos CLI |
| **TOTAL** | **150** | TypeScript skeletons |

> **Nota:** O projeto completo tem 6,604 arquivos TypeScript. Extraímos os 150 mais relevantes para referência.

## 🏗️ Arquitetura do Projeto

### Tipo de Arquitetura
**Monorepo com Workspace pnpm**

```
openclaw/
├── src/              # Core engine e gateway (2,571 arquivos TS)
├── extensions/       # Plugins de extensão (72 pacotes, 979 arquivos TS)
├── skills/          # Skills externos CLI (53 pacotes)
├── packages/        # Pacotes adicionais (clawdbot, moltbot)
├── apps/            # Aplicações móveis (iOS, Android)
├── ui/              # Interface web
└── docs/            # Documentação
```

## 📂 Estrutura de Skeletons

### src/ (100 arquivos)
```
src/
├── entry_skel.ts           # Ponto de entrada
├── index_skel.ts           # Exportações públicas
├── agents/                # Sistema de agentes
│   ├── lib_skel.ts
│   ├── spawn_skel.ts
│   ├── acp/
│   └── ...
├── channels/              # Sistema de canais
│   ├── config_skel.ts
│   ├── registry_skel.ts
│   ├── policies_skel.ts
│   └── ...
├── gateway/               # Servidor HTTP/WebSocket
│   ├── http_skel.ts
│   ├── websocket_skel.ts
│   ├── rpc_skel.ts
│   └── ...
├── providers/             # Auth providers
├── config/                # Sistema de configuração
├── cli/                   # Interface CLI
├── commands/              # Comandos CLI
├── memory/                # Sistema de memória
├── sessions/              # Gerenciamento de sessões
├── browser/               # Automação via Playwright
├── media/                 # Pipeline de mídia
├── cron/                  # Agendamento de tarefas
├── plugins/               # Sistema de plugins
├── security/              # Políticas de segurança
└── ... (50+ módulos)
```

### extensions/ (50 arquivos)
```
extensions/
├── discord/               # Canal Discord
│   ├── index_skel.ts
│   ├── client_skel.ts
│   ├── api_skel.ts
│   ├── channel_skel.ts
│   ├── send/
│   └── ...
├── google/                # Provider Google AI (Gemini)
│   ├── index_skel.ts
│   ├── oauth_skel.ts
│   ├── gemini-cli-provider_skel.ts
│   └── ...
├── diffs/                 # Visualização de diffs
│   ├── index_skel.ts
│   ├── tool_skel.ts
│   ├── config_skel.ts
│   └── ...
├── openai/                # Provider OpenAI
├── anthropic/             # Provider Anthropic/Claude
├── telegram/              # Canal Telegram
├── slack/                 # Canal Slack
├── signal/                # Canal Signal
├── whatsapp/              # Canal WhatsApp (oficial)
└── ... (72+ extensions)
```

## 🔌 Extensions Disponíveis (72 pacotes)

### Canais de Mensagem (22+)
- telegram, discord, slack, signal, whatsapp (oficial), line
- imessage (BlueBubbles), matrix, mattermost, feishu
- googlechat, irc, msteams, nextcloud-talk
- synology-chat, tlon, twitch, zalo, voice-call

### Model Providers (35+)
- openai, anthropic, google (Gemini), amazon-bedrock
- copilot-proxy, qwen-portal-auth, minimax-portal-auth, xai
- mistral, perplexity, huggingface, openrouter, together
- volcengine, venice, cloudflare-ai-gateway, nvidia
- ollama, vllm, node-llama-cpp, opencode, openshell

### Utilitários & Ferramentas (15+)
- memory-core, memory-lancedb, diagnostics-otel, diffs
- llm-task, lobster, open-prose, talk-voice
- test-utils, thread-ownership, device-pair, acpx
- phone-control, brave, firecrawl, github-copilot, zai

## 🛠️ Skills Disponíveis (53 pacotes)

### Sistema & CLI
- session-logs, tmux, model-usage, sherpa-onnx-tts

### Comunicação & Mensagem
- imsg, blucli, wacli

### Desenvolvimento & Git
- github, gh-issues, coding-agent

### Notas & Produtividade
- bear-notes, apple-notes, apple-reminders, obsidian
- notion, things-mac, trello

### Mídia & Conteúdo
- openai-whisper, openai-whisper-api, summarize
- openai-image-gen, video-frames, songsee
- spotify-player, sonoscli

### Web & Busca
- gifgrep, xurl, blogwatcher

### Sistemas & Serviços
- healthcheck, oracle, peeksboo, weather
- 1password, node-connect, openhue, ordercli, mcporter

### Ferramentas Especiais
- skill-creator, nano-banana-pro, nano-pdf
- canvas, camsnap, gemini, discord, slack

## 🎯 Funcionalidades Principais

| Funcionalidade | Descrição |
|---------------|-----------|
| **Gateway** | Servidor HTTP/WebSocket para controle e streaming |
| **Agents** | Sistema de agentes com ACP (Agent Client Protocol) |
| **Channels** | Sistema de canais de comunicação (22+ plataformas) |
| **Providers** | 35+ providers de modelos de IA |
| **Skills** | 53+ skills CLI externas |
| **Memory** | Sistema de memória vetorial |
| **Browser** | Automação via Playwright |
| **Media** | Pipeline de processamento de mídia |
| **Cron** | Agendamento de tarefas |
| **Security** | Políticas de segurança e validação |
| **Sandbox** | Execução segura de ferramentas |
| **A2UI** | Canvas UI para interfaces de agentes |

## 📖 Como Usar os Skeletons

### 1. Explorar API do Gateway
```bash
# Ver servidor HTTP
cat src/gateway/http_skel.ts

# Ver sistema de agentes
cat src/agents/lib_skel.ts

# Ver configuração
cat src/config/index_skel.ts
```

### 2. Entender Canais
```bash
# Ver canal Discord
cat extensions/discord/index_skel.ts

# Ver provider OpenAI
cat extensions/openai/index_skel.ts
```

### 3. Ver Arquitetura Completa
- Consulte `/inspiration/openclaw/README.md` para documentação completa
- Consulte `/inspiration/openclaw/AGENTS.md` para detalhes do sistema de agentes
- Consulte `ARCHITECTURE.md` (não criado ainda, veja README.md original)

## 🔄 Comparação com Outros Projetos

| Funcionalidade | OpenClaw | nullclaw | moltis | LobsterAI | nanobot | ironclaw |
|---------------|-----------|-----------|--------|-----------|---------|----------|
| **Agentes** | ✅ ACP | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Canais** | ✅ (22+) | ✅ (17) | ✅ (10+) | ❌ | ✅ (13) | ✅ |
| **Providers LLM** | ✅ (35+) | ✅ (50+) | ✅ | ✅ | ✅ (8) | ✅ |
| **Tools** | ✅ (Skills CLI) | ✅ (30+) | ✅ | ✅ | ✅ | ✅ (MCP) |
| **Skills** | ✅ (53+ CLI) | ✅ | ✅ | ✅ | ✅ | ✅ (WASM) |
| **Memory** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Gateway HTTP** | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **WebSocket** | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **Browser** | ✅ (Playwright) | ❌ | ✅ | ❌ | ❌ | ✅ |
| **Mobile Apps** | ✅ (iOS, Android) | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Electron** | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **TUI** | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |

## 📝 Notas Importantes

1. **Monorepo com pnpm**: O projeto usa workspace pnpm com 72+ pacotes
2. **Extensível**: Sistema de plugins bem definido com Plugin SDK
3. **Multi-plataforma**: macOS, Linux, Windows (WSL2), iOS, Android
4. **Self-hosted**: Pode rodar completamente local, sem dependência de cloud
5. **Large codebase**: 6,604 arquivos TypeScript no total

## 🔗 Referências

- **Documentação Original**: `/inspiration/openclaw/README.md`
- **AGENTS.md**: `/inspiration/openclaw/AGENTS.md` - Detalhes do sistema de agentes
- **VISION.md**: `/inspiration/openclaw/VISION.md` - Visão do projeto
- **CHANGELOG.md**: `/inspiration/openclaw/CHANGELOG.md` - Histórico de mudanças

## Licença

Consulte `/inspiration/openclaw/LICENSE` para termos de licenciamento do projeto original.
