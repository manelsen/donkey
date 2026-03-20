# CHECKLIST

Checklist operacional derivado do `ROADMAP.md`, cobrindo de F3 em diante.

## Convenção

- `[x]` concluído
- `[-]` em andamento
- `[ ]` pendente

## Ordem de ataque sugerida

1. F3 — Providers reais: alinhar capability declarada com capability real
2. F6 — Fechar export/view de `.md` sobre o backend semântico
3. F7 — Marketplace remoto de skills
4. F8 — Fechar canais chineses restantes
5. F9 — Admin e consolidação final de `ctl`

---

## F3 — Multi-provider

**Objetivo:** 5 providers funcionando com suas peculiaridades isoladas nos adapters, inclusive tool calling e streaming real.

### Base já pronta

- [x] `OpenRouterAdapter`, `AnthropicAdapter`, `GeminiAdapter`, `MiniMaxAdapter`, `ZhipuAdapter` com completions básicas
- [x] Seleção de provider por usuário em `PREFERENCES.md`
- [x] Fallback por sessão
- [x] `donkey ctl provider test <name>`

### Pendências operacionais

- [x] Implementar **Anthropic function calling** real
  Critério:
  `caps().toolCalling` bate com o runtime; request inclui tools; response suporta `tool_use`/`tool_result`.

- [x] Implementar **Gemini function calling** real
  Critério:
  `function_declarations` presentes no body; parsing de tool calls funcional; quirk `requiresUserFirst` refletido no histórico.

- [x] Corrigir **streaming real em OpenRouter**
  Critério:
  `makeStreamFn` deixa de ser fallback não-streaming; partials chegam incrementalmente.

- [x] Implementar **streaming real em Anthropic**
  Critério:
  SSE/event stream do adapter entrega tokens incrementalmente ao runtime.

- [x] Revisar `caps()` dos providers
  Critério:
  `toolCalling`, `streaming` e demais capacidades refletem o comportamento real, não intenção futura.

- [x] Expandir testes de contrato dos providers
  Cobrir:
  tool calling, streaming, fallback, normalização de payload, parsing de resposta.

- [x] Guard temporário no orquestrador para streaming com tools
  Estado:
  enquanto `StreamFn` ainda só representa texto, o primeiro round não usa streaming quando há tools disponíveis, evitando mascarar tool calls.

---

## F6 — Postgreyskull

**Objetivo:** fechar a lacuna entre backend semântico e export textual.

### Base já pronta

- [x] `PostgresMemoryAdapter`
- [x] pgvector + AGE
- [x] embeddings OpenRouter
- [x] `ctl memory search`
- [x] `ctl memory import`

### Pendências operacionais

- [x] Definir estratégia de `.md` como views do grafo
  Opções:
  export sob demanda via `ctl`, export no fechamento da sessão, ou ambos.
  Decisão:
  export sob demanda via `ctl memory export`.

- [x] Implementar export/view de `USER.md`, `MEMORY.md` e afins sobre o backend Postgres
  Critério:
  o usuário consegue obter a visão textual coerente sem depender do backend `.md`.

- [x] Cobrir export/view com testes
  Critério:
  export determinístico, sem divergência óbvia entre grafo/vetor e texto gerado.

---

## F7 — Skills Ecosystem

**Objetivo:** integrar marketplace Clawhub, com instalação e atualização remotas.

### Base já pronta

- [x] `SkillManifest`
- [x] `DenoSkillAdapter`
- [x] registry global/local
- [x] merge por usuário
- [x] load de user skills no bootstrap de sessão

### Pendências operacionais

- [x] Implementar HTTP client para registry remoto Clawhub
  Cobrir:
  busca, listagem e leitura de metadados.

- [x] Implementar download de skills
  Critério:
  skill remota é trazida e armazenada localmente de forma previsível.

- [x] Implementar verificação de hash/assinatura
  Critério:
  instalação remota não executa conteúdo sem validação.

- [x] Implementar `donkey ctl skill search <query>`

- [x] Implementar `donkey ctl skill install <name>` via registry remoto

- [x] Implementar `donkey ctl skill update`
  Critério:
  compara versão local e remota, com update explícito e seguro.

- [x] Expandir testes de registry/instalação
  Cobrir:
  manifests inválidos, drift de versão, falha de download, falha de validação.

---

## F8 — Channels chineses

**Objetivo:** completar a matriz de canais mapeados.

### Base já pronta

- [x] `WeComAdapter`
- [x] `FeishuAdapter`

### Pendências operacionais

- [x] Escolher direção de **QQ**
  Decisão aberta:
  OneBot v11/v12 ou API oficial.
  Decisão:
  OneBot v11, priorizando compatibilidade com bridges que já falam a API oficial do QQ.

- [x] Implementar `WeChatAdapter`
  Cobrir:
  OAuth 2.0, envio, recebimento, template messages e resolução de identidade.

- [x] Implementar `QQAdapter`
  Critério:
  protocol/client estabilizado conforme decisão acima.

- [x] Integrar novos canais ao runtime de sessão
  Critério:
  identidade, continuação de sessão, outbox e rebuild efêmero funcionam como nos canais atuais.

- [x] Expandir testes/fixtures dos canais novos

---

## F9 — TUI + Admin

**Objetivo:** fechar a operação/admin do daemon.

### Base já pronta

- [x] IPC socket
- [x] log ring buffer
- [x] `donkey ctl status`
- [x] `donkey tui`
- [x] instalação/remoção/start/stop/logs via service

### Pendências operacionais

- [x] Implementar user manager panel
  Cobrir:
  listar usuários, editar perfil, revogar acesso.

- [x] Consolidar `donkey ctl`
  Critério:
  comandos F1-F8 aparecem de forma consistente e previsível no CLI.

- [x] Revisar UX de TUI/admin
  Critério:
  ações administrativas críticas ficam descobertas e testáveis.

---

## Decisões abertas

- [x] F6 — `.md` como views do grafo: sob demanda, no fechamento da sessão, ou ambos
- [x] F8 — QQ: OneBot v11/v12 ou API oficial

---

## Marco atual

- [x] Base runtime/refactor concluída
  Estado:
  daemon, orchestrator, native tools, loader, bootstrap, sandbox, outbound e runtimes de canal foram fatiados, contratos frágeis corrigidos e testes de contrato ampliados.
