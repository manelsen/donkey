[PRD]
# PRD: Interfaces — endpoint OpenAI com o loop do agente e dashboard com gestão

> **Executor:** agente autônomo. Leia tudo antes de começar. Execute as histórias **na ordem**, cada uma com
> gates verdes e commit próprio.

## 1. Contexto

A V4 mede **Interfaces em 37%** (peso 8%, distância 59); a prioridade 2 é “endpoint OpenAI com o **loop do
agente** (tools/memória) e SSE; dashboard com gestão”. Hoje é mais estreito:

- `POST /v1/chat/completions` é proxy de provider (`app/openai_compat_runtime.chatReply`):
  `parseOpenAiChatRequest` **recusa** `stream` e `tools`; `POST /api/chat` é fire-and-forget.
- `/dashboard` é shell público read-only (sessões/providers só no blob de `/api/status`), e o outbox não tem
  dono de “fim de turno”: progresso (`🔧`), done e debug saem como `isPartial=false` e seriam confundidos com
  resposta final por uma correlação ingênua.

## 2. Objetivos

1. `/v1/chat/completions` roda o **mesmo turno** de um canal: debounce, memória, tools e sessão por usuário.
2. Contrato OpenAI: `chat.completion` e `chat.completion.chunk` por SSE com `[DONE]`, deltas e tool calls.
3. Correlação por identidade `api:<user>`, com deadline, limites de corpo/buffer e orçamento de workers.
4. Dashboard lê sessões e saúde de providers, executa **uma** ação e nenhum texto de canal vira conteúdo.

## 3. Fora de escopo

- Web UI completa, desktop app, ACP, i18n; `responses`, Anthropic/Gemini-shaped, embeddings, áudio, imagens.
- `tools`/`tool_choice` do cliente (seguem 400): o catálogo de tools é do agente.
- Revogar usuário, alternar provider, instalar skill ou editar config via HTTP (só `donkey ctl`).
- Rate limit por IP/token e fila de turnos: 1 turno em voo por `user` e 4 pendentes; sem cancelar o turno
  quando o cliente desconecta (o turno termina e o resultado é descartado).
- Editar `app/session_bootstrap.nim` e `domain/providers/*` (donos: missões de tools/provider-transport).

## 4. Quality gates

Obrigatórios ao fim de **toda** história:

```bash
bash scripts/check_boundaries.sh && nimble build -y && JOBS=6 bash scripts/run_tests.sh && git diff --check
```

- TDD: teste primeiro, **falha mostrada**, implementação mínima, verde.
- `domain/` puro (`func`), app/adapter só liga, `raise` só em adapter e I/O falível em `Result[T, string]`;
  nenhum teste novo usa rede, provider real, socket real, `sleep` real ou Docker.
- Nenhum teste existente é editado para “acomodar”; se precisar mudar, o comportamento mudou e a história
  diz isso. Worktree sujo ao começar: **pare** e registre, sem stash/reset alheio.

### 4.1 Ciclo, donos e preparação

Um teste novo por passo, rodado sozinho; a saída vermelha entra no relato; implementação mínima; o mesmo teste
até verde; gates; commit com as duas linhas do vermelho → verde.

**Donos (um escritor por vez).** `http_gateway.nim`, `src/donkey.nim` e `domain/message.nim` são serializados:
US-001 escreve `domain/message.nim`; US-002 escreve `http_gateway.nim`, `src/donkey.nim`,
`tool_loop_runtime.nim` e `core/tooling/tool_loop.nim`; US-003 só volta a `http_gateway.nim` **depois** de
US-002; US-004 depois de US-003. Só US-001 é disjunta da missão de ferramentas. Onde este PRD divergir de
`tasks/roadmap-v4.md` (remoção de `t_openai_compat` em US-002, dono de `src/donkey.nim`), vale **este
documento**; registre a divergência no commit, sem editar o roadmap.

Antes da US-001: `git status --short` (sujo: pare), pull `--ff-only` em `master`, branch
`feat/interfaces-agent-api`, e o commit de abertura declara este PRD como fonte de verdade da missão.

## 5. Histórias

### US-001: Contrato puro, semântica de resposta e ponte de correlação
**Descrição:** contrato puro do turno, marcadores de resposta e ponte thread-safe chaveada por usuário.

**Critérios de aceite:**
- [ ] `domain/gateway/identity_pure.nim`: `apiUserId*(raw)` aceita `[a-z0-9._-]{1,64}`, recusa `.`/`..`,
      barras e maiúsculas, e devolve `UserId("api:" & normalizado)`; `isApiChatReply*(msg)` é verdadeiro só
      para `$msg.userId` com prefixo `api:` — **sem** `replyTo`/`channelId`.
- [ ] `domain/gateway/chat_request.nim`: `AgentChatRequest` e `parseAgentChatRequest*` (400
      `invalid_request_error`/`unsupported_parameter`): `user` obrigatório e última mensagem `user`;
      `system`/`developer`, `tools`, `tool_choice`, `response_format` e `n > 1` recusados; `temperature`,
      `top_p` e `max_tokens` ignorados; histórico anterior ignorado (a sessão é dona dele).
- [ ] `domain/message.nim` (aditivo): `ReplyKind` (`rkChannel`, `rkToolNotice`, `rkDebug`, `rkFinalAnswer`,
      `rkTurnError`), `ToolCallNotice` e campos `replyKind*`, `toolCall*`, `inputTokens*`, `outputTokens*`;
      construtores existentes compilam e canais ignoram os campos novos.
- [ ] `domain/gateway/chat_response.nim` e `domain/gateway/redact_pure.nim`: `buildAgentChatResponse`,
      `buildAgentChunk` (`object: "chat.completion.chunk"`, `delta.role` só no 1º, `finish_reason` só no
      último), `buildAgentError`, `sseDone()`, `deltaText*` e `redactForClient*` (remove `Bearer …`, `sk-…`,
      `key=…`, `token=…`, trunca em 300).
- [ ] `app/chat_bridge.nim` e `domain/gateway/capacity_pure.nim`: `ChatBridge` (`Lock` + pending table)
      chaveada por `$userId` (`register`, `deliver`, `fail`, `poll`, `abandon`), com `now`/`nap` injetados,
      nunca `sleep` real; `MaxTurnBufferBytes = 256 * 1024` (marca `truncated`), segundo turno do mesmo
      `userId` → `ChatBridgeBusy`, mensagem sem entrada pendente **descartada**. `admitLongLived*` aplica
      `MaxPendingTurns = 4`, `MaxConcurrentSseConnections = 4` e `MaxLongLivedWorkers = 6`, deixando 2 dos 8
      workers para `/health`, `/dashboard`, `/api/status`, `/api/logs` e `/v1/models`.
- [ ] `tests/domain/gateway/t_chat_contract.nim` e `tests/app/t_chat_bridge.nim`: `user` ausente e com `../`,
      `stream`, `tools`, `deltaText`, precedência de `replyKind`, parcial+final, buffer truncado, deadline com
      relógio falso, mesmo usuário recusado, entrega tardia e admissão; `parseOpenAiChatRequest` e
      `tests/domain/providers/t_openai_compat.nim` intocados.

### US-002: `/v1/chat/completions` não-streaming com o loop do agente
**Descrição:** a chamada roda um turno real do agente e devolve `chat.completion`, com exatamente uma resposta.

**Critérios de aceite:**
- [ ] `app/agent_chat_runtime.nim`: `runAgentChat*(body, bridge, dispatch, authorize, tokenConfigured, now)`
      mapeia 503 sem `DONKEY_HTTP_TOKEN`, 400 do parser, 403 por `authorize` (`avRevoked`/`avNotAllowed`),
      413 quando `body.len > MaxApiRequestBytes` (1 MiB, mesmo limite do gateway), 429 `ChatBridgeBusy`,
      504 deadline, 502 `rkTurnError` e 200 com `usage`; `authorize` roda **antes** de `dispatch`, então a
      recusa do ingress (`session_ingress.nim`) não é alcançada e nenhum texto de recusa vira conteúdo.
- [ ] `dispatch` recebe `InboundMessage(userId: apiUserId, channel: ckCli, channelId: $userId, text: turnText)`
      e usa o **mesmo** `handleGatewayFallback` de `/api/chat`, sem segundo caminho de sessão. Em
      `src/donkey.nim`, antes de `routeOutbound`: `isApiChatReply(msg)` entrega à `ChatBridge` e **não** vai ao
      porta CLI; `rkFinalAnswer`/`rkTurnError` fecham o turno, `rkToolNotice` vira evento de tool e
      `rkDebug`/`rkChannel` são descartados. `authorize` é fiado ao mesmo `isRevoked`/DM policy do ingress.
- [ ] Marcação no turno (`app/tool_loop_runtime.nim`): progresso e `buildToolLoopDoneText` levam
      `replyKind: rkToolNotice` + `toolCall` (`phase: "start"|"done"`), o texto final de `finalizeNormalTurn` e
      o de `streamToOutbox` levam `rkFinalAnswer`, a explicação de erro de provider leva `rkTurnError` e o
      `debugText` leva `rkDebug`; o texto dos canais não muda. Regra: **`toolCall`/`rkToolNotice` nunca é
      conteúdo**. `usage` decidido: `UsageTotals` + `addUsage*` em `core/tooling/tool_loop.nim` somam
      `inputTokens`/`outputTokens` de **todas** as rodadas (inclusive streamadas) em `ToolLoopRunResult`,
      copiados para a `rkFinalAnswer`; o bridge repassa ao corpo.
- [ ] `GatewayCompletionFn`/`chatReply` saem de `app/http_gateway.nim` e `app/openai_compat_runtime.nim` e
      `tests/app/t_openai_compat.nim` sai junto — mudança declarada: 400/503/502 passam ao teste novo.
- [ ] `tests/app/t_agent_chat.nim` com `dispatch`/`authorize`/relógio falsos: 200 + `usage`, 400 `system`, 403,
      429 concorrente, 504 deadline, 413 corpo grande, dois `user` com `UserId` distintos e um turno com tool
      produzindo **uma** resposta sem `🔧` no `content`; `addUsage*` coberto em
      `tests/core/t_tool_loop_usage.nim` (soma de rodadas normal e streamada).

### US-003: SSE com chunk OpenAI, tool calls e limites
**Descrição:** `stream: true` recebe chunks incrementais e a atividade de tools sem conexão pendurada.

**Critérios de aceite:**
- [ ] `app/agent_chat_stream.nim`: `runAgentStream*(userId, bridge, send: proc(chunk: string): bool, limits,
      nap)` testável sem socket: role → deltas de `content` (parciais coalescidos por `deltaText`; a
      `rkFinalAnswer` substitui e fecha o restante) → deltas de `tool_calls` a partir de `toolCall` → chunk
      final com `finish_reason` + `usage` → `data: [DONE]`. Limites: `MaxSseChunksPerTurn = 4096` e
      `DONKEY_HTTP_AGENT_TIMEOUT_SEC` (default 120, máx 600), com keepalive `: ping` a cada 15 s e relógio/nap
      injetados; estouro encerra com `finish_reason: "length"` + `[DONE]`.
- [ ] `send` falso (cliente saiu) → `bridge.abandon` e slot liberado, **sem** cancelar o turno; mensagens
      tardias daquele `userId` são descartadas; erro no meio emite `{"error":...}` redigido + `[DONE]`.
- [ ] `http_gateway.nim` (após US-002): a rota `stream: true` usa `admitLongLived` antes de bloquear o worker
      (429 se o orçamento estourar), conta em `MaxPendingTurns` e deixa `MaxConcurrentSseConnections` só para
      `/api/events`. `tests/app/t_agent_chat_stream.nim`: ordem dos chunks, `tool_calls` sem texto de canal
      misturado, coalescência de parciais, `length` no estouro, desconexão no 2º chunk, 429 e `[DONE]`.

### US-004: Dashboard: sessões, providers e nova conversa
**Descrição:** leitura de sessões e saúde de providers e **uma** ação de gestão, sem segundo escritor de memória.

**Critérios de aceite:**
- [ ] `domain/gateway/dashboard_pure.nim`: `buildSessionsJson*(rows, limit, offset)` (`sessionId`, `userId`,
      `channels`, `lastInboundAt` ISO, `live`), `buildProvidersJson*(availability, cooldowns, metrics)`
      (`id`, `available`, `cooldownUntil`, `calls`, `ok`, `err`, `avgLatencyMs`, `health` =
      `ok|degraded|cooling|missing`), `parseSessionAction*` (allowlist `{new}`) e `parseSessionTaskPath*`
      (prefixo `/api/sessions/`, sufixo `/task`, userId **cru**, sem barras).
- [ ] `app/session_manager.listSessionDetails*()` (aditivo) expõe `sessionId`, `lastInboundEpochMs` e
      `restored`, sem mudar `SessionInfo` do IPC. Hooks `GatewaySessionsFn`, `GatewayProvidersFn` e
      `GatewaySessionActionFn` declarados em `app/http_gateway.nim` e fiados em `src/donkey.nim`;
      `routeGatewayRequest` mantém igualdade exata e a rota parametrizada entra por `parseSessionTaskPath`.
- [ ] `GET /api/sessions` e `GET /api/providers` (não públicas, Bearer): `limit` default 50, máx 200, `offset`
      ≥ 0, inválidos clampados (nunca 500), health com ids de `providerDescriptor`.
- [ ] `POST /api/sessions/{userId}/task` → 404 quando a chave crua não existe em `sm.entries` (**não** passa
      por `apiUserId`, que prefixaria `api:`), 403 se `isRevoked`, 202 e `ensureSessionTask(..., tkNew, "")`
      (mesmo `tkNew` de `handleControlTask`, mapeado em `tests/adapters/channel/t_telegram_runtime.nim` e
      `tests/core/t_command_catalog.nim`).
- [ ] `buildDashboardHtml` ganha as tabelas e o botão **“nova conversa”** (fetch com Bearer + `setInterval`),
      com CSP `default-src 'none'` e nenhum dado inline do servidor. `tests/app/t_dashboard_api.nim` e
      `tests/app/t_dashboard_action.nim`: shapes 200, clamp, 202 com hook chamado uma vez com `tkNew`, 404 para
      UUID inexistente, 403, 400 `{"kind":"reset"}`, 401 sem token e redação de `sk-fake`/`key=`/`Bearer x`.

### US-005: Documentar e fechar a missão
**Descrição:** a próxima pessoa entende contrato, limites e a postura de autenticação sem ler o código.

**Critérios de aceite:**
- [ ] Criar `docs/topics/http-gateway.md` com rotas, autenticação, orçamento de workers (6 long-lived, 2
      reservados), limites, streaming, semântica de `user`/sessão, ausência de cancelamento e a justificativa do
      503 sem `DONKEY_HTTP_TOKEN` (o `/api/chat` histórico segue local-only); reescrever a seção
      “OpenAI-Compatible API” de `docs/reference/configuration.md` (hoje “not the agent loop”), incluir
      `DONKEY_HTTP_AGENT_TIMEOUT_SEC` na tabela de env e confirmar por `rg` que não sobrou `chatReply`,
      `GatewayCompletionFn`, `openai_compat_runtime` nem “not the agent loop”.
- [ ] O commit registra que a missão é de produto, não de arquitetura, e que a V5 reavalia Interfaces.

## 6. Requisitos funcionais

- **FR-1:** O turno da API é o mesmo de canal: ingress → ator → memória → tools → outbox, sem bifurcação.
- **FR-2:** Identidade é `api:<user>` sanitizada; sessão, histórico e paddock são por usuário.
- **FR-3:** Tools do cliente seguem recusadas; tool calls do agente são informativos para o cliente.
- **FR-4:** Só `rkFinalAnswer`/`rkTurnError` fecham o turno; `toolCall`/`rkToolNotice` nunca são conteúdo.
- **FR-5:** Todo caminho (200, streaming, erro, desconexão, deadline) libera o slot da ponte e do worker.
- **FR-6:** Erros e dashboard passam por `redactForClient`; `/api/sessions`, `/api/providers` e a ação exigem
  Bearer e, sem token, o endpoint de agente é 503.

## 7. Não-objetivos

- `tools` do cliente, `response_format`, `n > 1`, replay de histórico do cliente.
- `ChannelKind` novo para a API (decidido: `ckCli` + prefixo `api:`); persistir turnos em ledger.
- Autenticação por usuário, rate limit por token/IP, auditoria de acesso; gestão de providers e skills; cancelar
  o turno no `abandon` e reservar worker fixo por endpoint.

## 8. Métricas de sucesso

- Dois turnos via `/v1/chat/completions` mantêm contexto e memória; turno com tool emite `tool_calls` no SSE e
  termina em `finish_reason: "stop"` com **um** texto; erros (400/401/403/413/429/502/504) cobertos, zero
  `sk-`/`key=`/`Bearer ` nos payloads, nenhum teste dormindo de verdade e suíte verde sem editar teste existente
  além da remoção declarada em US-002.

## 9. Questões em aberto

- `ckCli` + prefixo `api:` basta, ou vale `ChannelKind` próprio na segunda superfície? Revisar na V5.
- Honrar `system` do cliente exigiria overlay de prompt; a ação de gestão exige `DONKEY_HTTP_ADMIN_TOKEN`
  separado? Por ora o token de instância cobre.
[/PRD]
