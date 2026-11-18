# Review — `tasks/prd-interfaces.md` (V4 prioridade 2)

**Verdict: PASS WITH FIXES.** O recorte é o certo (turno real + SSE + leitura/1 ação no dashboard) e o reúso de
`handleGatewayFallback` evita o segundo orquestrador. Mas a correlação resposta↔pedido **não funciona como
escrita**, e há dois vazamentos de UX de canal para o cliente OpenAI. Nada exige replanejar; os itens 1–4 são
pré-requisito da US-002.

## 1. Loop do agente e correlação
- Turno real ✓: `dispatch` → `handleGatewayFallback` (`src/donkey.nim:1506`) → `handleDaemonSessionFallback` →
  `startSessionIngress` (`session_ingress.nim:263`). Sessão/memória/tools vêm do ator existente; nenhum caminho novo.
- **`ckCli` + `replyTo "api-"` é impossível.** `sessionReplyTo` (`session_bootstrap.nim:359-365`) devolve `""` para
  `ckCli`, e as mensagens de progresso (`tool_loop_runtime.nim:341`) nem carregam `replyTo`. Logo `isApiChatReply`
  nunca casa e o "🔧 …" do canal vaza para o porta CLI. **Fix:** `isApiChatReply(msg)` = `$msg.userId` com prefixo
  `api:` (puro, testável; `apiUserId` já garante unicidade) e **não** editar `session_bootstrap.nim` (dono é
  provider/ferramentas). Resposta tardia (turno abandonado) = descartada, não roteada.
- 403 **não é implementável** com `runAgentChat(body, bridge, dispatch, tokenConfigured, nowSec)`: o ingress já
  responde DM-negado/revogado por outbox (`session_ingress.nim:273-284`, `367-380`) e retorna. **Fix:** injetar
  `authorize: proc(userId): AuthVerdict` (ou `dispatch` devolvendo `Result`) + teste de 403.
- `user`→`UserId` ✓; "dois user … turnos independentes" **não** é observável com `dispatch` falso (só ids distintos).

## 2. SSE
- Shape de chunk, `[DONE]`, `finish_reason`, `length`, `send` falso ✓.
- **Vazamento de texto de canal:** progresso (`🔧 tool…`) e `buildToolLoopDoneText` (`tool_loop_runtime.nim:592-599`)
  chegam como `isPartial=false`; o bridge os tomaria como resposta final. **Fix:** "mensagem com `toolCall` nunca é
  conteúdo" — preencher `toolCall` também no done (ou `kind` aditivo), e o final = `isPartial=false` sem `toolCall`.
- O turno **pode streamar internamente** (`streamFn != nil`, `tool_loop_runtime.nim:433`): US-002 recebe parciais e
  precisa coalescer via `deltaText` (a última mensagem não é necessariamente o texto integral). Dizer isso.
- Desconexão: detecção só na escrita (até 15 s de ping) e o turno continua consumindo tokens após `abandon`.
  Declarar que não há cancelamento (ou chamar `requestTurnInterrupt`).
- Worker budget: 8 workers (`http_gateway.nim:591`), `MaxPendingTurns=4` + SSE 4 não deixa folga para
  `/api/status`, `/dashboard` e `/api/events` (até 120 s). Fixar orçamento por endpoint + 429/503 *antes* de ocupar
  worker. §8 ("MaxPendingTurns de 8 workers") contradiz `MaxPendingTurns = 4`.

## 3. Dashboard
- Sem build de front-end ✓ (HTML + `fetch` + `textContent`), CSP preservado ✓.
- **`POST /api/sessions/{userId}/task` passa por `apiUserId` → prefixa `api:` e o lookup em `sm.entries` (UUID
  interno) dá 404 sempre.** Validar como userId cru existente. `routeGatewayRequest` é igualdade exata de path:
  a rota parametrizada e os hooks `sessions/providers/action` (e `isRevoked`, `src/donkey.nim:1260`) não têm dono
  declarado — enumerar em `http_gateway`/`src/donkey`.
- Botão "encerrar" ≠ allowlist `{new}`: renomear para "nova conversa" (ou `tkStop`, fora de escopo).
- `tests/app/t_orchestrator_control.nim` **não existe** (só binário velho); citar `t_telegram_runtime.nim:69`, `t_command_catalog.nim`.

## 4. Verificabilidade
- `usage`: `ToolLoopRunResult` não tem tokens e as rodadas descartam `CompletionResponse.inputTokens/outputTokens`.
  §10 deixa em aberto algo de que o aceite depende → decidir agora (soma de todas as rodadas, inclusive stream).
- `ChatBridge` precisa de relógio/`sleep` injetados: sem isso o teste de 504 dorme 120 s e o ping 15 s.
- 413 >1 MiB é do gateway (`http_gateway.nim:429-436`), inalcançável em `runAgentChat`; remover do `t_agent_chat`
  ou checar o mesmo limite no runtime.

## 5. Ownership e não-objetivos
- US-003 e US-004 **editam `http_gateway.nim`**: não são paralelas; só US-001 é disjunta de ferramentas.
  `core/tooling/tool_loop.nim` (soma de tokens) entra na lista de donos. `roadmap-v4:47` atribui `src/donkey.nim` +
  `domain/message.nim` a US-003/US-004 e o PRD a US-002 — reconciliar. Remoção de `t_openai_compat` é US-002 aqui e
  US-003 em `roadmap-v4:58`.
- Não-objetivos ok (web UI/desktop/ACP/i18n ✓). Faltam: **rate/latência** (não há limite de requisições; só 1 turno
  em voo por usuário + 4 pendentes; turnos sequenciais ilimitados) e "sem worker reservado".
- 503 sem `DONKEY_HTTP_TOKEN` muda a postura local-only vs `/api/chat`: justificar e documentar na US-005.

**Ordem:** US-001 (contrato+bridge; separar bridge se o vermelho ficar grande) → US-002 (portão serializado) →
US-003 → US-004 → US-005. Sem paralelismo em `http_gateway.nim`.
