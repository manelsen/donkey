# Donkey — UX Backlog (gerado 2026-03-18)

## Estado atual (feat/ux-p1 — já implementado)

| Feature | Canal | Status |
|---------|-------|--------|
| `/start` | Telegram | ✅ |
| `/help` (HTML, lista completa) | Telegram | ✅ |
| `/reset` | Telegram | ✅ |
| `/memory` — exibe MEMORY.md | Telegram | ✅ |
| `/mycode` — gera OTP cross-channel | Telegram + Discord | ✅ |
| `/continue <code>` — consome OTP | Discord (slash cmd) | ✅ |
| `/models` — inline keyboard picker 2 níveis | Telegram | ✅ |
| `⚙️` reaction — enviada antes de processar, deletada com resposta | Telegram | ✅ |
| `setMyCommands` — menu de comandos no startup | Telegram | ✅ |
| `callback_query` — inline button handler com ack automático | Telegram | ✅ |
| Discord WebSocket gateway real (ws_client próprio) | Discord | ✅ |
| Discord REST send/edit/interaction | Discord | ✅ |
| Streaming partial edits (`streamId` + `editMessage`) | Telegram + Discord | ✅ |

---

## Backlog P0 — Alta prioridade

### 1. Typing loop periódico durante processamento
**Inspiração:** OpenClaw `runtime-telegram-typing.ts` — refresh a cada 4 s (Telegram) / 8 s (Discord)
**Por que importa:** usuário vê chat congelado durante pensamento longo do LLM
**Implementação:** Chronos `asyncSpawn` por turn que envia `sendChatAction("typing")` a cada 4 s; cancelado quando `globalOutbox` entrega a resposta
**Arquivo:** `src/donkey/app/orchestrator.nim` + `src/donkey/adapters/channel/telegram.nim`

### 2. Emoji lifecycle completo: 🔄 → ⚙️ → ✅ / ❌
**Inspiração:** OpenClaw `reaction-lifecycle` — queued🔄 → processing⚙️ → done✅ / error❌, removidos após reply
**Por que importa:** feedback visual claro do estado do pipeline
**Estado atual:** apenas ⚙️ enviado, deletado ao responder. Falta:
- 🔄 quando mensagem entra na fila (debounce ainda acumulando)
- ✅ atualizar o ⚙️ para ✅ antes de deletar
- ❌ quando LLM retorna erro
**Arquivo:** `src/donkey.nim` (drain globalOutbox) + `orchestrator.nim` (erro handling)

### 3. Session keying para grupos do Telegram
**Inspiração:** NullClaw — sessões por `chat_id`, não `user_id`
**Por que importa:** em grupos, cada chat deve ter sua própria sessão (e contexto)
**Estado atual:** `InboundMessage.userId` é sempre o UUID do usuário, mesmo em grupos
**Implementação:** adicionar `chatId` ao `InboundMessage`; `ensureSession` usa `chatId` como chave de sessão quando canal é grupo

### 4. `/continue <código>` no Telegram
**Estado atual:** apenas Discord tem `/continue` como slash command; Telegram tem `/mycode` mas não `/continue`
**Implementação:** handler `if cmd.startsWith("/continue ")` no daemon Telegram

### 5. `/forget` — apaga memórias
**Inspiração:** NullClaw `memory forget <key>`, OpenClaw `/forget`
**Implementação:** `memory.clearMemory(userId)` + confirmação

---

## Backlog P1 — Médio prazo

### 6. `/doctor` — diagnóstico do sistema
**Inspiração:** NullClaw `nullclaw doctor` — verifica: provider connectivity, memory files, tool clients, config
**Implementação:** proc `runDoctor()` que testa cada componente e formata relatório

### 7. `/model` — exibe modelo atual com ✓
**Inspiração:** NullClaw `/model` — mostra provider:modelo atual e routing status
**Estado atual:** `/models` permite selecionar mas não exibe o atual com ✓ destacado
**Implementação:** ler `PREFERENCES.md` e marcar o botão ativo com ✓

### 8. Supressão de `<thinking>` no streaming
**Inspiração:** Pincer — buffer 250 ms, suprime preview de `<thinking>...</thinking>`
**Implementação:** filtro no `streamToOutbox` do orchestrator: acumula tokens sem flush enquanto dentro de `<thinking>`

### 9. `/ping` — latência do provider
**Inspiração:** OpenClaw `/ping` — mede round-trip do provider atual
**Implementação:** `buildCompleteFn` + mensagem "ping" + mede `epochMs()` delta

### 10. Fallback de provider automático
**Inspiração:** OpenClaw provider fallback chain
**Estado atual:** `buildFallbackFn` existe mas não é usado quando provider primário falha mid-session
**Implementação:** wrap do `completeFn` com retry sobre fallbacks antes de retornar erro ao usuário

---

## Backlog P2 — Pós-F2

### 11. `/think [off|low|medium|high]` — controle de reasoning
**Inspiração:** NullClaw `/think`, OpenClaw command argument menus
**Implementação:** inline keyboard com os 4 níveis → salvo em `PREFERENCES.md`

### 12. `/status` — snapshot da sessão
**Inspiração:** NullClaw `nullclaw status`
**Conteúdo:** provider ativo, modelo, nº turns, memórias salvas, tools carregadas, uptime

### 13. `/debug` — modo verbose na sessão
**Inspiração:** NullClaw `/debug`
**Implementação:** flag na sessão → orchestrator loga tokens e tool calls como mensagem para o usuário

### 14. History persistido (JSONL)
**Inspiração:** NullClaw `history list/show`
**Implementação:** ao fechar sessão, serializar `ConversationHistory` em `data/users/{uuid}/sessions/{id}.jsonl`

### 15. Outbound media no Telegram
**Inspiração:** OpenClaw — bot envia imagens, documentos
**Implementação:** `OutboundMessage.mediaUrl` + `sendPhoto`/`sendDocument` no TelegramAdapter

### 16. Discord modals para `/continue`
**Inspiração:** OpenClaw — modal input para código OTP em vez de slash command com opção

---

## Arquitetura de referência dos comandos (NullClaw pattern)

```
InboundMessage.text
    │
    ▼
parseCommand(text) → CommandPlan
    ├── LocalCommand  → handler imediato (sem LLM)
    │     /start, /help, /reset, /memory, /forget,
    │     /models, /model, /ping, /status, /doctor,
    │     /mycode, /continue, /callback
    └── LlmTurn       → ensureSession() → orchestrator
```

Hoje o daemon faz `if cmd == "/x"` inline — vale extrair para `parseCommand` quando o número de comandos justificar.

---

## Arquivos-chave

| Arquivo | Responsabilidade |
|---------|-----------------|
| `src/donkey.nim` | Daemon: routing de comandos, drain do globalOutbox |
| `src/donkey/app/orchestrator.nim` | Turn loop: debounce → LLM → tool → reply |
| `src/donkey/adapters/channel/telegram.nim` | API Telegram: send, typing, keyboard, status |
| `src/donkey/adapters/channel/discord.nim` | Gateway WS + REST Discord |
| `src/donkey/adapters/identity/identity_resolver.nim` | UUID cross-channel, OTP pairing |
| `src/donkey/adapters/memory/md_file.nim` | MEMORY.md, PREFERENCES.md, USER.md |
| `src/donkey/core/pipeops.nim` | `\|>`, `>>=`, `nowMs`, `splitChunks` |
