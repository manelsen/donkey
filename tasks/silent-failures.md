# Silent Failure Inventory

Inventario completo de padroes `isOkOr: discard` e `except CatchableError: discard`
em caminhos operacionais do Donkey.

Gerado em: 2026-04-10
Branch: `us/us-001-silent-failure-inventory`

---

## 1. `isOkOr: discard` — 23 ocorrencias

Padrao: o resultado de uma operacao que pode falhar e' explicitamente descartado
sem log, metrica ou retorno.

### 1.1 Outbound (envio de mensagens) — 19 ocorrencias

| # | Arquivo | Linha | Contexto |
|---|---------|-------|----------|
| 1 | `src/donkey.nim` | 156 | `tg[].sendTyping(userId)` — typing indicator em polling loop |
| 2 | `src/donkey.nim` | 1210 | `tgAdapter.sendTyping(msg.userId)` — typing ao processar mensagem Telegram |
| 3 | `src/donkey/adapters/channel/telegram_runtime.nim` | 664 | `tgAdapter.send(...)` — feedback de comando `reasoning` |
| 4 | `src/donkey/adapters/channel/telegram_runtime.nim` | 706 | `tgAdapter.send(...)` — feedback de comando de sessao (debug/reset/new/etc) |
| 5 | `src/donkey/adapters/channel/qq_runtime.nim` | 246 | `qqAdapter.send(...)` — resposta `lcaShowAbout` |
| 6 | `src/donkey/adapters/channel/qq_runtime.nim` | 248 | `qqAdapter.send(...)` — resposta `lcaStartIntro` |
| 7 | `src/donkey/adapters/channel/qq_runtime.nim` | 261 | `qqAdapter.send(...)` — resposta `lcaSkillCommand` |
| 8 | `src/donkey/adapters/channel/qq_runtime.nim` | 267 | `qqAdapter.send(...)` — resposta `lcaGenerateLinkCode` |
| 9 | `src/donkey/adapters/channel/qq_runtime.nim` | 270 | `qqAdapter.send(...)` — resposta `lcaClearMemory` |
| 10 | `src/donkey/adapters/channel/qq_runtime.nim` | 276 | `qqAdapter.send(...)` — resposta `lcaDoctorReport` |
| 11 | `src/donkey/adapters/channel/qq_runtime.nim` | 282 | `qqAdapter.send(...)` — resposta `lcaHelpText` |
| 12 | `src/donkey/adapters/channel/qq_runtime.nim` | 288 | `qqAdapter.send(...)` — resposta `lcaShowMemory` |
| 13 | `src/donkey/adapters/channel/qq_runtime.nim` | 295 | `qqAdapter.send(...)` — resposta `lcaContinueLink` |
| 14 | `src/donkey/adapters/channel/qq_runtime.nim` | 310 | `qqAdapter.send(...)` — feedback de comando de sessao |
| 15 | `src/donkey/adapters/channel/qq_runtime.nim` | 318 | `qqAdapter.send(...)` — resposta `crPing` |
| 16 | `src/donkey/adapters/channel/qq_runtime.nim` | 335 | `qqAdapter.send(...)` — resposta `crStatus` |
| 17 | `src/donkey/adapters/channel/wecom_runtime.nim` | 48 | `wcAdapter.send(...)` — helper `wcReply` |
| 18 | `src/donkey/adapters/channel/wecom_runtime.nim` | 53 | `wcAdapter.send(...)` — fallback text em `wcMd` |
| 19 | `src/donkey/adapters/channel/feishu_runtime.nim` | 72 | `fsAdapter.send(...)` — resposta `lcaSkillCommand` |
| 20 | `src/donkey/adapters/channel/feishu_runtime.nim` | 85 | `fsAdapter.send(...)` — resposta `crSessionTask` |
| 21 | `src/donkey/adapters/channel/feishu_runtime.nim` | 100 | `fsAdapter.send(...)` — resposta `crUi` |
| 22 | `src/donkey/adapters/channel/feishu_runtime.nim` | 106 | `fsAdapter.send(...)` — resposta `crPing` |
| 23 | `src/donkey/adapters/channel/feishu_runtime.nim` | 112 | `fsAdapter.send(...)` — resposta `crStatus` |

### 1.2 Classificacao por camada

| Camada | Count | Criticidade |
|--------|-------|-------------|
| Outbound (Telegram) | 4 | Media — typing indicators e feedback de comando |
| Outbound (QQ) | 12 | Alta — todas as respostas de comandos podem falhar silenciosamente |
| Outbound (WeCom) | 2 | Alta — respostas diretas ao usuario |
| Outbound (Feishu) | 5 | Alta — respostas de comandos e status |

---

## 2. `except CatchableError: discard` — 26 ocorrencias

Padrao: excecoes capturaveis sao silenciadas completamente em blocos try/except.

### 2.1 Heartbeat / Reminder — 3 ocorrencias

| # | Arquivo | Linha | Contexto |
|---|---------|-------|----------|
| 1 | `src/donkey/app/heartbeat.nim` | 69 | `runAllTasks` — falha em qualquer heartbeat task e' silenciada |
| 2 | `src/donkey/app/heartbeat.nim` | 92 | `runCommitmentReview` — falha no sink de review e' silenciada |
| 3 | `src/donkey/app/heartbeat.nim` | 120 | `deliverDueReminders` — falha no outbox de reminder e' silenciada |

### 2.2 Embedding / LLM — 1 ocorrencia

| # | Arquivo | Linha | Contexto |
|---|---------|-------|----------|
| 4 | `src/donkey/adapters/embedding/openrouter_embed.nim` | 52 | `embedText` — falha no parse da resposta de embedding e' silenciada |

### 2.3 Webhook / Channel servers — 11 ocorrencias

| # | Arquivo | Linha | Contexto |
|---|---------|-------|----------|
| 5 | `src/donkey/adapters/channel/wechat.nim` | 265 | `respond` — falha ao enviar resposta HTTP |
| 6 | `src/donkey/adapters/channel/wechat.nim` | 323 | `close` — falha ao fechar conexao do cliente |
| 7 | `src/donkey/adapters/channel/ws_client.nim` | 143 | `wsClose` — falha ao enviar frame de fechamento WebSocket |
| 8 | `src/donkey/adapters/channel/wecom.nim` | 167 | `sendHttpReply` — falha ao enviar resposta HTTP WeCom |
| 9 | `src/donkey/adapters/channel/wecom.nim` | 180 | `close` — falha ao fechar conexao do cliente WeCom |
| 10 | `src/donkey/adapters/channel/wecom.nim` | 266 | `close` — falha ao fechar conexao no thread webhook |
| 11 | `src/donkey/adapters/channel/qq.nim` | 100 | `respond` — falha ao enviar resposta HTTP QQ |
| 12 | `src/donkey/adapters/channel/qq.nim` | 144 | `close` — falha ao fechar conexao do cliente QQ |
| 13 | `src/donkey/app/http_gateway.nim` | 130 | `sendResponse` — falha ao enviar resposta HTTP |
| 14 | `src/donkey/app/http_gateway.nim` | 142 | `sendSseHeaders` — falha ao enviar headers SSE |
| 15 | `src/donkey/app/http_gateway.nim` | 245 | `send` — falha ao enviar heartbeat comment SSE |

### 2.4 Memory / Persistence — 5 ocorrencias

| # | Arquivo | Linha | Contexto |
|---|---------|-------|----------|
| 16 | `src/donkey/adapters/memory/postgres_memory.nim` | 201 | `saveUserMd` — falha ao executar AGE cypher query |
| 17 | `src/donkey/adapters/memory/postgres_memory.nim` | 224 | `appendMemory` — falha ao executar AGE cypher query |
| 18 | `src/donkey/adapters/memory/postgres_memory.nim` | 260 | `search` — falha ao executar AGE cypher para enriquecimento |
| 19 | `src/donkey/adapters/memory/postgres_memory.nim` | 276 | `deleteUser` — falha ao executar AGE cypher para deletar |
| 20 | `src/donkey/adapters/memory/md_file.nim` | 512 | `loadDueReminders` — falha ao parsear JSON de reminder |

### 2.5 Ferramentas / Native — 5 ocorrencias

| # | Arquivo | Linha | Contexto |
|---|---------|-------|----------|
| 21 | `src/donkey/app/native_tools.nim` | 414 | `walkFind` — falha ao traversar diretorio |
| 22 | `src/donkey/app/native_tools.nim` | 460 | `grepFile` — falha ao ler arquivo para grep |
| 23 | `src/donkey/app/native_tools.nim` | 475 | `grepDir` — falha ao traversar diretorio para grep |
| 24 | `src/donkey/app/native_tools.nim` | 535 | `performFetch` — falha ao parsear JSON de resposta HTTP |
| 25 | `src/donkey/adapters/tools/browser.nim` | 298 | `close` — falha ao fechar WebSocket do browser |

### 2.6 Principal (donkey.nim) — 1 ocorrencia

| # | Arquivo | Linha | Contexto |
|---|---------|-------|----------|
| 26 | `src/donkey.nim` | 157 | `sendTyping` wrapper — falha ao enviar typing no polling loop |

### 2.7 Classificacao por camada

| Camada | Count | Criticidade |
|--------|-------|-------------|
| Heartbeat / Reminder | 3 | Alta — reminders podem nao ser entregues sem nenhum registro |
| Webhook / Channel | 11 | Media — erros de conexao sao comuns, mas sem log dificulta diagnostico |
| Memory / Persistence | 5 | Alta — falhas em operacoes de grafos e reminders nao sao visiveis |
| Ferramentas / Native | 5 | Baixa-Media — alguns casos sao esperados (file not found) |
| Embedding / LLM | 1 | Alta — falha de embedding afeta busca semecia silenciosamente |
| HTTP Gateway | 1 | Baixa — SSE heartbeat em conexao ja fechada e' esperado |

---

## 3. Resumo geral

| Padrao | Count | Camadas afetadas |
|--------|-------|-----------------|
| `isOkOr: discard` | 23 | Outbound (Telegram, QQ, WeCom, Feishu) |
| `except CatchableError: discard` | 26 | Heartbeat/Reminder, Webhook, Memory, Tools, Embedding, Gateway |
| **Total** | **49** | |

## 4. Priorizacao para proximas historias

### Critica (deve emitir retorno explicito + log)
- `heartbeat.nim:120` — `deliverDueReminders`: reminder delivery falha silenciosamente
- `openrouter_embed.nim:52` — embedding falha sem registro, afeta busca semecia
- Todas as ocorrencias em `qq_runtime.nim` (12x) — respostas de usuario podem sumir
- Todas as ocorrencias em `feishu_runtime.nim` (5x) — respostas de usuario podem sumir

### Importante (deve emitir pelo menos log)
- `heartbeat.nim:69,92` — heartbeat tasks e commitment review falham sem registro
- `postgres_memory.nim:201,224,260,276` — operacoes AGE falham sem registro
- `md_file.nim:512` — reminders corrompidos sao ignorados sem log

### Aceitavel (silencio pode ser OK, mas log seria melhor)
- Webhook channel servers (wechat, wecom, qq) — erros de conexao sao esperados
- `ws_client.nim:143` — close de WebSocket pode falhar normalmente
- `http_gateway.nim:245` — SSE heartbeat em conexao fechada e' esperado
- `browser.nim:298` — cleanup de browser pode falhar
