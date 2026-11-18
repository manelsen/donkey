# Desenho — A1/A2/A3 (dono único da thread do turno)

Resposta aos itens A1/A2/A3 de `deferred-findings-v4.md`. Read-only; nenhum
código foi alterado. Decisão: **A1 opção (c) — mover o dispatch para a thread do
daemon**, usando a mesma fila de comandos que A2 precisa.

## Por que (c)

Hoje o outbox é um `AsyncQueue` sem lock (`src/donkey.nim:328`, criado em
`:726`, drenado em `:1609-1622`) e os dois caminhos de ingress chamam código de
aplicação **no worker HTTP**: `gwInboundFn` (`:1227-1228`, ligado também como
`agentDispatchFn`) e `gwSessionActionFn` (`:1264-1300`). `ensureSessionTask`
muta o `SessionManager`; o `apiChatNap` bombeia o dispatcher do worker atual,
mas o ator pode nascer nele e ficar sem bomba se o turno for servido por outro.

| Opção | O que muda | Corrige | Raio |
|---|---|---|---|
| (a) canal MPSC + drenador no daemon | troca o tipo do outbox; ~29 assinaturas e 31 escritas; `send` bloqueante deadlocka, `trySend` descarta | só A1 | grande |
| (b) lock explícito no put/get | mesmo ripple, e não segura lock no `await put` do tool loop; uma escrita esquecida reintroduz a corrida | só A1 | grande |
| **(c) dispatch no daemon** | workers só **enfileiram** um comando; o daemon aplica (`handleGatewayFallback`, `ensureSessionTask`) e portanto cria todo ator no dispatcher do daemon | **A1 + A2 + raiz de A3** | pequeno: 1 módulo novo + wiring; **zero** mudança nos 31 escritores do outbox |

Depois de (c), todo caminho que escreve no `globalOutbox` roda no daemon (atores
de canal, heartbeat, scheduler, reminders, fallback, `/api/chat`, `/v1`,
dashboard). O único artefato cross-thread restante é o `ChatBridge`, que já é
protegido por lock.

## Mudanças (c + A2)

Novo `src/donkey/app/ingress_command_queue.nim`:

- `IngressCommandKind = ickInbound | ickSessionAction`
- `IngressOutcome = ioAccepted | ioNotFound | ioRevoked | ioDropped | ioBusy | ioUnavailable`
- `IngressReply` — lock, `abandoned`, `refs`, `Channel[IngressOutcome]` (mesmo
  protocolo refcounted de `provider_executor.nim:78-89`)
- `openIngressQueue`/`closeIngressQueue`/`trySubmit`/`submitAndWait`/
  `drainIngressCommands(apply)`/`complete`/`releaseReply`
- `IngressQueueDepth = 256`, `MaxCommandsPerTick = 64`

Em `src/donkey.nim`:

- `gwEnqueueFn` (para `inboundFn`), `gwDispatchFn` (para `agentDispatchFn`;
  levanta quando `io* != ioAccepted`, e o `except` existente do runtime mapeia
  para 502 antes de abrir o stream);
- `gwSessionActionFn` vira submit/wait com `SessionActionTimeoutMs = 2000`;
- `applyIngressCommand`/`applySessionAction` — corpos antigos, agora no daemon;
- `handleGatewayFallback` passa a devolver `bool` (aceito/descartado);
- estágio `withIngressCommands` no `runDaemonTick`, **antes** do `withOutboxDrain`;
- `openIngressQueue` antes do bootstrap; dreno/fechamento no `finally`.

Em `http_gateway.nim`:

- `GatewayInboundFn` devolve `bool` (`/api/chat` mapeia false → 503);
- `gsaoUnavailable` no enum de ação, mapeado para 503.

**Não muda:** `session_ingress`, `session_manager`, `orchestrator`,
`tool_loop_runtime`, `onboarding_runtime`, `native_tools`, `approval_runtime`,
`subagent_runtime`, `chat_bridge`, `agent_chat_runtime`.

## A2 — ação do dashboard

Mesma fila, `ickSessionAction`. O worker submete e espera; o daemon aplica:
404 (`rawUserId notin sm.entries`), 403 (`authorizeDaemonUser`), 202
(`ensureSessionTask` retornou). Timeout de 2 s → 503, com `abandoned` marcado
sob lock; comando já tomado pelo daemon conclui e a resposta é descartada
(refcount). Fila cheia → 503 imediato.

## A3 — SSE

A1 torna a **causa raiz** obsoleta: o ator vive no daemon e é bombeado pelo loop
(`await sleepAsync`). O que resta no worker é transporte: `bridge.poll`,
keepalive e abort — sem mudança de mecânica. `apiChatNap` pode virar `os.sleep`
e o override `agentStreamNapFn` sai. O abort continua usando `bridge.abandon`;
com A4, o abandono deve passar o `turnToken`.

## Ordem de passos (compila em cada um)

| Passo | Mudança | Prova |
|---|---|---|
| 0 | módulo novo + teste, sem wiring | `t_ingress_command_queue.nim`: 8 produtores × 100, exatamente-uma-vez, thread id do outbox == consumidor; timeout sem sleep real; abandonado não aplica; fila cheia → `ioBusy` |
| 1 | `gsaoUnavailable` → 503 | `t_dashboard_action`: 503 quando o daemon não reconhece |
| 2 | wiring A2 | `t_dashboard_action` ponta a ponta com consumidor fake (202/404/403/timeout/thread id) |
| 3 | wiring A1 | `t_agent_chat`: dispatch rejeitado → 502 antes de qualquer byte |
| 4 | limpeza A3 | `t_agent_chat`: stream conclui com o turno em outra thread; keepalive com relógio fake |
| 5 | docs e remoção de parâmetros mortos | suíte completa + boundary |

Passos 0–2 = PR de A2; 3–4 = PR de A1/A3.

## Riscos

- **Head-of-line no loop do daemon:** todo turno passa a compartilhar o loop.
  Já é verdade para Telegram/Discord; chamadas de provider já vão para o
  `provider_executor`. Mitigação: log quando um tick passar de 200 ms.
- **Fila cheia vira 503 no `/api/chat`:** documentar que 202 significa "daemon
  aceitou"; 256 de fila e 64 por tick são folgados para 8 workers.
- **Timeout após o daemon tomar a ação:** o apply completa, então um retry pode
  duplicar `/new`. Dedupe por request id é follow-up.
- **`ipcStatusFn` ainda lê `sm` no worker** (`donkey.nim:1180-1186`): mesma
  família de H*, não é regressão deste bloco — declarar no PR.
- **`Channel[T]` move o valor:** `InboundMessage` não pode ser usado depois do
  `trySend`.
