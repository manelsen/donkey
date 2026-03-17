---
name: Donkey — decisões arquiteturais
description: Decisões de design do projeto Donkey tomadas até agora
type: project
---

Donkey é um sistema de agentes IA ("Claw") em Nim, self-hosted VPS, equipe corporativa pequena.

**Linguagem:** Nim puro, aspirações embedded (minimal deps)
**Async:** Chronos (não asyncdispatch)
**Skills/MCP:** ToolPort unificado — Deno subprocess + MCP client (mesmo protocolo JSON-RPC/stdio)
**Memória F1:** arquivos .md no workspace do usuário
**Memória F2+:** PostgreSQL + pgvector + Apache AGE ("Postgreyskull")
**Embeddings:** qwen3-embedding-8b via OpenRouter (4096 dims)
**Providers v1:** Zhipu Coding (URL própria), OpenRouter, Google Gemini (= "OpenCode Zen")
**Channels v1:** Telegram → Discord → chineses
**Config:** TOML
**Secrets:** nimcrypto (ChaCha20-Poly1305 + PBKDF2, pure Nim, zero deps C), DONKEY_MASTER_KEY env var
**Interface:** CLI + TUI, sem web
**Skills ecosystem:** Clawhub (npm packages, rodam como Deno subprocesses)
**Arquitetura:** Hexagonal, ports como Nim concepts, functional core com `func`
**Multi-agente:** Actor model com Chronos AsyncChannel, OrchestratorAgent por sessão
**Sessões:** pertencem ao usuário (UUID), cross-channel via `/continue`
**User workspace:** data/users/{uuid}/ com .md legíveis (padrão USER.md do OpenClaw com frontmatter)
**Binary:** `donkey` (daemon), `donkey ctl` (admin CLI)

**Quirks de provider conhecidos:**
- OpenRouter: requer HTTP-Referer e X-Title em todo request
- Zhipu: formato de tools nativo (GLM), native tools (web_search, code_interpreter) via caps()
- Gemini: function calls devem vir após model turns; formato functionCall/functionResponse ≠ OpenAI

**F1 scope:** Telegram + Zhipu Coding + memória .md + MCP client + bootstrapping onboarding conversacional

**Why:** usuário tem paixão por arquitetura hexagonal e TDD (Red-Green-Refactor obrigatório)
**How to apply:** nunca escrever código antes do teste; core domain sempre em `func`; adapters nunca importados pelo core
