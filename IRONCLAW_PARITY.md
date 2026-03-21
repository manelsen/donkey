# IronClaw Parity — Donkey Gap Analysis

Baseado em:

- [`inspiration/ironclaw/README.md`](/home/micelio/git/donkey/inspiration/ironclaw/README.md)
- [`inspiration/ironclaw/FEATURE_PARITY.md`](/home/micelio/git/donkey/inspiration/ironclaw/FEATURE_PARITY.md)
- [`inspiration/ironclaw/docs/smart-routing-spec.md`](/home/micelio/git/donkey/inspiration/ironclaw/docs/smart-routing-spec.md)
- [`inspiration/ironclaw/docs/LLM_PROVIDERS.md`](/home/micelio/git/donkey/inspiration/ironclaw/docs/LLM_PROVIDERS.md)

Este documento não tenta copiar a arquitetura do IronClaw. O objetivo é mapear paridade funcional útil para o Donkey atual.

## Legenda

- `[x]` já temos no Donkey
- `[-]` temos parcial
- `[ ]` ainda não temos
- `[>]` próximo alvo recomendado

## 1. Segurança e sandbox

- `[x]` sandbox Docker configurável para `bash`
- `[x]` isolamento por paddock/workspace por usuário
- `[x]` enforcement de path dentro do paddock
- `[x]` proteção básica contra SSRF em `web_fetch`
- `[x]` hardening básico de output de tool no histórico com envelope não-instrucional
- `[ ]` leak detection de segredos em request/response de tools
- `[ ]` credential injection no host boundary com política explícita
- `[x]` policy explícita de rede por tool/skill com host e prefixo de path para tools web
- `[ ]` rate limiting por tool
- `[ ]` resource limits mais finos por tool/job além do sandbox atual
- `[ ]` sandbox WASM real para tools não confiáveis

## 2. Gateway e operação contínua

- `[x]` daemon central com sessões por usuário
- `[x]` IPC com `status` e `logs`
- `[x]` TUI básica
- `[x]` health/status operacional via CLI e IPC
- `[-]` doctor de sistema existe, mas ainda não é um subsistema profundo tipo IronClaw
- `[ ]` HTTP gateway/web UI com SSE/WebSocket
- `[ ]` broadcast de eventos de agente para clientes conectados
- `[ ]` hot reload de configuração
- `[ ]` heartbeat system para execução proativa de manutenção
- `[ ]` self-repair/stuck operation recovery
- `[ ]` health monitor de canais com restart automático

## 3. Canais

- `[x]` Telegram
- `[x]` Discord
- `[x]` WeCom
- `[x]` Feishu
- `[x]` WeChat runtime base
- `[x]` QQ runtime base
- `[-]` WeChat inbound real ainda pendente
- `[-]` QQ / OneBot inbound real ainda pendente
- `[ ]` Signal
- `[ ]` Slack channel real
- `[ ]` WhatsApp
- `[ ]` HTTP webhook channel genérico
- `[ ]` Web gateway chat channel
- `[ ]` channel health monitor
- `[ ]` stream drafting / partials ricos em canais além de Telegram/Discord
- `[ ]` per-channel tool policies

## 4. Agent runtime

- `[x]` sessões por usuário
- `[x]` cross-channel identity e `/continue`
- `[x]` orchestrator + workers
- `[x]` subtask/job runtime básico (`task`, `await`, `cancel_job`)
- `[x]` failover básico de provider por sessão
- `[x]` skills Deno + MCP
- `[x]` compaction/sumarização de contexto
- `[-]` subagentes existem como surface operacional básica, mas não como sistema amplo de agentes especializados comparável ao IronClaw
- `[ ]` global sessions opcionais
- `[ ]` session pruning automática
- `[ ]` compaction model override
- `[ ]` post-compaction audit/injection de contexto
- `[ ]` thinking modes amplos (`off/minimal/low/medium/high/xhigh/adaptive`) no runtime inteiro
- `[ ]` tool-level streaming
- `[ ]` block-level streaming rico
- `[ ]` stuck loop detection com backoff
- `[ ]` llms.txt discovery

## 5. Provider layer

- `[x]` OpenRouter
- `[x]` Anthropic
- `[x]` Gemini
- `[x]` MiniMax
- `[x]` Zhipu
- `[x]` OpenAI-compatible via OpenRouter-style base
- `[ ]` OpenAI adapter dedicado
- `[ ]` Ollama
- `[ ]` Bedrock
- `[ ]` smart model routing por complexidade
- `[ ]` provider telemetry de roteamento
- `[ ]` reasoning/thinking defaults por modelo

## 6. Tools e extensibilidade

- `[x]` MCP
- `[x]` Deno skills
- `[x]` tools nativas fortes de arquivo, shell, web, sessão e jobs
- `[x]` ClawHub registry/instalação
- `[-]` bundles remotos ainda entram como skill de instrução, não como runtime executável completo
- `[ ]` dynamic tool building no estilo IronClaw
- `[ ]` plugin architecture de hot drop sem restart
- `[ ]` tool policies mais expressivas por canal/usuário
- `[x]` allowlist de URLs por tool web (`fetch`/`web_fetch`/`web_search` obedecem policy explícita)
- `[ ]` suppressToolErrors configurável
- `[ ]` intent-first tool display

## 7. Memória e dados

- `[x]` memória Markdown
- `[x]` Postgres + pgvector + AGE
- `[x]` embeddings OpenRouter
- `[x]` identidade persistente por usuário
- `[x]` workspace filesystem por usuário
- `[-]` busca híbrida existe, mas não está descrita como RRF explícito e afinada no nível do IronClaw
- `[ ]` audit log completo de tool executions como produto de primeira classe
- `[ ]` richer owner-scope separation como conceito explícito

## 8. CLI e operação

- `[x]` `start`, `ctl`, `service`, `tui`, `status`, `memory`, `skills`, `pairing`, `sandbox`, `doctor`, `logs`
- `[x]` `cron` base
- `[-]` `channels` parcial
- `[ ]` `gateway start/stop`
- `[ ]` `message send`
- `[ ]` `agents`
- `[ ]` `sessions`
- `[ ]` `webhooks`
- `[ ]` `browser`
- `[ ]` `backup`
- `[ ]` `update`
- `[ ]` `/subagents spawn`
- `[ ]` `/export-session`

## 9. Próximos alvos recomendados

### P0

- `[>]` ingress real de WeChat
- `[>]` ingress real de QQ / OneBot
- `[>]` leak detection de segredos em request/response de tools

### P1

- `[>]` smart model routing por complexidade
- `[>]` Ollama provider
- `[>]` HTTP/web gateway com SSE
- `[>]` event broadcast do runtime

### P2

- `[>]` Signal ou Slack como próximo canal “alto valor”
- `[>]` heartbeat/proactive runtime
- `[>]` richer tool policies por canal
- `[>]` bundles remotos do ClawHub executáveis de ponta a ponta

## 10. Minha leitura

O Donkey já atingiu boa paridade com o IronClaw em:

- runtime básico multi-canal
- memória persistente
- providers centrais
- MCP/skills
- sandbox Docker
- operação por daemon/TUI/IPC

O maior gap restante não é “mais um provider” nem “mais uma tool”.
O maior gap está em:

- hardening de segurança de tool/runtime
- gateway contínuo com eventos/streaming para clientes
- automação contínua (`heartbeat`, webhooks, rotinas mais ricas)
- canais mais maduros e com inbound real
- roteamento inteligente de modelo
