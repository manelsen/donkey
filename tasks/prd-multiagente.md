[PRD]
# PRD: Fan-out paralelo de subagentes e observabilidade do turno pai

> **Executor:** agente autônomo. Leia o documento inteiro antes de começar.
> Execute as histórias **na ordem**; cada uma termina com os gates verdes e um commit
> próprio. Não abra a seguinte com a anterior vermelha.

## 1. Contexto

O Donkey já delega **um** filho isolado com paddock, allowlist e orçamento próprios
(`app/subagent_runtime.nim`, `domain/subagent_pure.nim`). Falta o **fan-out**: N filhos
independentes no mesmo turno, agregados deterministicamente, com cancelamento de irmãos e
visibilidade no turno pai.

| Hoje | Efeito |
|---|---|
| `spawn_subagent` cria 1 filho; `await_subagent` aceita 1 id | N tarefas = N chamadas |
| tool calls do round rodam em série (`app/tool_loop_runtime.nim:331`) | espera serial, sem visão do conjunto |
| `suppressProgress = true` (`app/subagent_runtime.nim:246`) | pai não vê progresso por filho |
| `SubagentResult` conta tokens, mas não soma | orçamento agregado inexistente |

O `hermes-agent` cobre o domínio com rooms/relay/Kanban; **nada disso entra**. O recorte é o
item 3 da seção 6 da V4 — fan-out paralelo — mais a observabilidade mínima para confiar no
agregado. Esta missão **não fecha** o item 3 da V4 (rooms/relay ficam fora) e **não move** o
placar; ela entrega o fan-out.

## 2. Objetivos

1. Plano **puro** (tarefas/tools/orçamentos por filho + teto agregado) que falha fechado antes
   de criar workspace.
2. Runtime que dispara N filhos concorrentes, cada um com sessão, histórico, paddock e
   orçamento próprios, e agrega em ordem determinística.
3. `fail_fast` (default) cancela irmãos na primeira falha/timeout; `collect_all` é opt-in.
4. Observabilidade no turno pai: desfecho por filho, tokens e uma linha por filho concluído.
5. Zero mudança no `spawn_subagent` singular e no isolamento já testado.

## 3. Fora de escopo

Rooms, relay, Kanban, agentes entre hosts/usuários; workers persistentes; memória compartilhada
entre irmãos; custo em USD (`SubagentResult.hasCost` nunca é preenchido hoje); dashboard/TUI
novos; substituir `spawn_subagent`/`await_subagent`.

## 4. Quality gates

Obrigatórios ao fim de **toda** história:

```bash
bash scripts/check_boundaries.sh
nimble build -y
JOBS=6 bash scripts/run_tests.sh
git diff --check
```

Adicional em US-003, US-004 e US-005 (concorrência): `bash scripts/run_stress_tests.sh`.
Regras, sem exceção: TDD com o vermelho mostrado antes da implementação; lógica pura em
`domain/` como `func`; proibido `raise` fora de adapter; I/O falível devolve
`Result[T, string]`; nenhum teste novo usa rede, provider real, Docker ou sleep como prova;
nenhum teste existente é editado para "acomodar" a mudança. Por história: rodar o teste novo
sozinho (`bash scripts/run_tests.sh <arquivo>`), mostrar a falha, implementar o mínimo até
verde, rodar os gates e commitar com a evidência vermelho → verde.

### 4.1 Escritores e paralelização

- `domain/fanout_pure.nim`: **um escritor** (US-001 → US-002). `app/subagent_runtime.nim`:
  US-003 → US-004 → US-005 → US-006, em sequência.
- `domain/subagent_pure.nim` também é desta missão: US-005 (`SubagentInfo.fanoutId`) → US-006
  (`SubagentHardDeniedTools`), um escritor por vez.
- **Colisão entre PRDs:** `domain/more_tools.nim`, `app/native_tools.nim`,
  `core/tooling/native_tool_dispatch.nim` e `app/session_bootstrap.nim` são compartilhados com
  `tasks/prd-ferramentas.md` (US-003/US-006); `app/session_bootstrap.nim` também é do
  `tasks/prd-provider-transport.md` (US-001). Ordem de escrita: provider US-001 → ferramentas
  US-003/US-006 → **multiagente US-006** (por isso a tool é a penúltima história).
- Cada subagente declara os arquivos que possui; testes de histórias diferentes podem ser
  escritos em paralelo (cada história é dona do seu arquivo).
- Suíte completa e commits são **sequenciais na sessão principal** (binários colidem).

## 5. Preparação (antes da US-001)

1. `git status --short`. Pare **somente** se um arquivo desta missão estiver sujo:
   `domain/fanout_pure.nim`, `domain/subagent_pure.nim`, `app/subagent_runtime.nim`,
   `domain/more_tools.nim`, `app/native_tools.nim`, `core/tooling/native_tool_dispatch.nim`,
   `core/agent_events.nim`, `app/session_bootstrap.nim`, `docs/topics/subagents.md`. Sujeira das
   missões de provider/ferramentas **não** bloqueia. Nunca use stash, reset ou checkout sobre
   trabalho alheio.
2. `git fetch && git switch master && git pull --ff-only`. O worktree já contém a missão de
   provider (13 commits desde `42b579a9`, `quirks.nim` removido, `t_provider_identity` e
   `t_descriptor_factory` novos): trabalhe sobre ela, não reverta.
3. Branch `feat/subagent-fanout`; commit de abertura aponta este PRD como fonte de verdade e
   registra o **baseline medido hoje** com `JOBS=6 bash scripts/run_tests.sh` (não hardcode
   contagem).
4. **Dependência de `tasks/prd-provider-transport.md`:** sem dependência de API; a dependência
   é de processo (gates, baseline) e de um arquivo compartilhado (`session_bootstrap.nim`, ver
   §4.1).

## 6. Histórias

### US-001: Plano puro de fan-out e orçamento agregado
**Descrição:** validar o conjunto (forma, tools e orçamento) antes de criar qualquer filho.

**Critérios:**

- [ ] Criar `src/donkey/domain/fanout_pure.nim` com `FanoutTask` (`task`, `context`, `tools`, `limits`), `FanoutLimits` (`maxChildren`, `maxAggregateTokens`, `maxAggregateDurationMs`), `FanoutPlan`, `planFanout*(tasks, limits, availableTools: openArray[string]): Result[FanoutPlan, string]`, `FanoutMaxChildren* = 8`, `FanoutAbsoluteMaxAggregateTokens* = 512_000`.
- [ ] Recusa 0 tarefas, > 8, tarefa vazia; valida o filho por `subagentRequestError(task, 0)`; tool pedida ausente de `availableTools` → `tool '<x>' is not available in this session`; soma dos `maxTokens` clampados > `FanoutAbsoluteMaxAggregateTokens` → `aggregate token budget exceeded: <soma> > <teto>`; `maxAggregateTokens` (runtime) acima do absoluto → erro (são tetos distintos).
- [ ] Ordem = entrada, índice estável `0..N-1`, planos iguais para entrada igual; `tests/domain/t_fanout_pure.nim` cobre 0/1/8/9, tarefa vazia, `bash`, tool indisponível, estouro e determinismo.
- [ ] `rg -n "chronos|adapters/|app/|httpclient" src/donkey/domain/fanout_pure.nim` vazio; `check_boundaries.sh` exit 0.

### US-002: Agregação determinística, sinal e política de parada
**Descrição:** a ordem de conclusão não muda o resultado; stop reason e cancelamento são puros e testáveis.

**Critérios:**

- [ ] Tipos em `fanout_pure.nim`: `FanoutChildOutcome` (`index`, `subagentId`, `status`, `text`, `error`, `usage`, `cancelledBySibling`, `durationMs`), `FanoutPolicy` (`fpFailFast`, `fpCollectAll`), `FanoutStopReason` (`fsrNone`, `fsrSpawnFailed`, `fsrChildFailed`, `fsrChildTimedOut`, `fsrSessionStop`, `fsrAggregateBudget`) e `FanoutSignal` (`spawnFailed`, `stopRequested`, `budgetExceeded`).
- [ ] `FanoutAggregate` (`fanoutId`, `policy`, `children`, `stopReason`, `ok`, `failed`, `timedOut`, `cancelled`, `totalTokens`, `totalDurationMs`) e `aggregateFanout*(plan, outcomes, fanoutId, policy, signal: FanoutSignal): FanoutAggregate` — o `signal` é o que produz `fsrSpawnFailed`/`fsrSessionStop`/`fsrAggregateBudget`.
- [ ] `stopReason` = primeiro **failure** por índice (`ssFailed`/`ssTimedOut`), ignorando `ssCancelled` e `cancelledBySibling`; precedência `spawnFailed` > `stopRequested` > `budgetExceeded` > failure. `fanoutShouldCancelSiblings*(agg, policy)` é `true` só com failure em `fpFailFast` e nunca reage a `ssCancelled` (o runtime guarda `cancelIssued` para não repetir a cada tick).
- [ ] `fanoutBudgetDecision*(totalTokens: int; limits: FanoutLimits): BudgetDecision` (usa `bdTokensExceeded` com o teto de runtime), `fanoutDeadlineMs*(plan)`, `fanoutProgressDue*(lastMs, nowMs, intervalMs = 1_000): bool`, `renderFanout*` (JSON com `timed_out`, chaves estáveis) e `fanoutProgressText*` (1 linha ≤ 200 chars) são puros.
- [ ] `tests/domain/t_fanout_aggregate.nim`: ordem invertida → JSON idêntico; irmão cancelado não vira stop reason; signal × failure; soma de tokens; decisão de orçamento. `t_subagent_pure.nim` sem edição.

### US-003: Runtime `startFanout`/`spawnFanout`
**Descrição:** disparar N filhos concorrentes, expor os ids e devolver um agregado determinístico.

**Critérios:**

- [ ] `FanoutHandle` (`fanoutId`, `childIds`) e `startFanout*(mgr; parent: NativeCtx; plan: FanoutPlan; policy: FanoutPolicy): Future[Result[FanoutHandle, string]]`: **sequencial** `await mgr.spawn` por tarefa. `spawn` é `{.async.}` mas não tem `await` interno, então os N filhos começam juntos; não usar `awaitSubagent` por filho.
- [ ] **Falha parcial de spawn:** aborta o plano; para cada filho já criado marca `usage.cancelled`, cancela o future, aguarda settlement (≤ 2 s) e só então remove o paddock. `startFanout` devolve `err("spawn failed for child <i>: ...")`; `spawnFanout` converte em agregado com `signal.spawnFailed = true` e `children` = os filhos criados e cancelados. Teste: port de workspace que falha no 2º `create`, 3 tarefas, `create`/`remove` casados, nenhum filho vivo.
- [ ] `spawnFanout` = `startFanout` + `awaitFanout*(mgr; fanoutId; stopGeneration; userId; userInterrupt): Future[FanoutAggregate]`; `FanoutState` fica em `mgr.fanouts: Table[string, FanoutState]` (handle, supervisor, agregado, `done`) **nos dois modos**, contado em `maxConcurrent`. Cada filho mantém `SessionState`, `ConversationHistory`, `SubagentUsage`, inbox/outbox e paddock próprios; o `ref` de usage é criado por filho.
- [ ] Se `running + plan.len > mgr.maxConcurrent`, falha antes de criar paddock (`running` já inclui filhos de fan-outs detachados; a tabela `fanouts` não conta em dobro). `fpFailFast`: no primeiro failure, cancela irmãos via `cancelSubagent`, marca `cancelledBySibling` e para — teste: 2º filho `ssFailed`, 1º/3º `ssCancelled` + `cancelledBySibling`, stop reason `fsrChildFailed`.
- [ ] Barreira (não sleep): 3 filhos com `parent.asyncCompleteFn` (o `completeFn` síncrono bloquearia a thread e daria deadlock, não timeout) esperando `contador == 3`; `maxDurationMs ≥ 2_000`; timeout da barreira 1,5 s. `paddockDirFor` distinto e ordem do agregado igual à do plano.

### US-004: Stop, teto agregado em runtime e shutdown
**Descrição:** `/stop`, estouro do teto e shutdown derrubam o fan-out inteiro sem órfãos nem futures pendentes.

**Critérios:**

- [ ] O supervisor (de `spawnFanout` ou detachado) checa `isSessionStopRequested`/`isUserStoppedSince` a cada 100 ms, sinaliza `stopRequested`, cancela os filhos vivos e devolve `fsrSessionStop` com parciais.
- [ ] **Teto de runtime:** no tick **e** na conclusão de cada filho, soma `usage.inputTokens + outputTokens` dos ids vivos, chama `fanoutBudgetDecision(total, plan.limits)`; em `bdTokensExceeded` sinaliza `budgetExceeded`, cancela todos e devolve `fsrAggregateBudget`. Teste com teto 20 e filhos consumindo 10+15: o 3º é cancelado e o stop reason é `fsrAggregateBudget` (prova o gatilho, não só a soma da US-005).
- [ ] **Settlement antes de cleanup:** `settleChild(rt)` marca `usage.cancelled`, `cancelSoon()`, aguarda `withTimeout(rt.future, 2_000)` e só então `workspace.remove`. `cancelSubagent` deixa de remover o paddock antes do settlement (a remoção passa para o `finally` de `runChild`/`settleChild`). Teste não-vacuoso: port espião grava `create:<id>` e, no `remove`, o resultado de `childSettled(mgr, id)` (helper exportado); exige `settled=true` em todo `remove` e `#remove == #create` — remoção precoce falha.
- [ ] `cancelAll` percorre `mgr.children` **e** `mgr.fanouts`, cancela supervisors detachados e espera ≤ 2 s; teste `tests/app/t_subagent_fanout_stop.nim`: 8 filhos, stop e shutdown no meio, `subagents/` vazio, zero futures pendentes, `removes == creates`.
- [ ] `cancel_subagent` de um irmão derruba os demais com `fpFailFast` e não os derruba com `fpCollectAll` (documentado na US-007).

### US-005: Observabilidade no turno pai
**Descrição:** ver o fan-out progredir e saber quanto custou em tokens, sem esperar o último filho em silêncio.

**Critérios:**

- [ ] `src/donkey/core/agent_events.nim`: `aekFanoutStart`/`aekFanoutDone` ("fanout_start"/"fanout_done", dois kinds, não um) e campo `fanoutId*: string` (vazio fora de fan-out); `kindLabel`/`toJson` incluem `fanoutId` só quando não vazio.
- [ ] `subagent_runtime.nim` emite `fanout <id> start children=N` e `fanout <id> done ok=.. failed=.. timed_out=.. cancelled=.. tokens=.. reason=..`; eventos de filho herdam o `fanoutId`.
- [ ] Progresso: no máximo **um** `OutboundMessage(isPartial=true)` por filho concluído; a decisão usa `fanoutProgressDue` (US-002) com `lastProgressMs` no estado do fan-out — sem host de clock novo em `NativeCtx`.
- [ ] Outcomes são capturados **quando cada filho termina** (o `pruneChildren` com retenção 64 pode descartar um filho não lido); o agregado soma tokens de todos, inclusive falhos/cancelados.
- [ ] `SubagentInfo` ganha `fanoutId*: string`; `list_subagents` o expõe e `SubagentInfo.toJson` inclui `fanout_id` só quando não vazio, sem alterar os outros campos.
- [ ] `tests/core/t_fanout_events.nim` (kinds, render, `fanoutId` vazio) e `tests/app/t_fanout_observe.nim` (throttle puro, agregado, listagem); `t_agent_events.nim` passa sem edição.

### US-006: Tool `spawn_subagents`
**Descrição:** expressar o fan-out em uma chamada, com ids imediatos quando `wait=false` e agregado quando `wait=true`.

**Critérios:**

- [ ] `src/donkey/domain/more_tools.nim`: `SpawnSubagentsToolName* = "spawn_subagents"`, schema com `tasks` (objetos com `task`, `context`, `tools`, `max_tool_calls`, `max_tokens`, `max_duration_sec`), `fail_fast` e `wait` (default `true`).
- [ ] `native_tools.nim`: `StartFanoutFn*`/`AwaitFanoutFn*` em `NativeCtx`, `SpawnFanoutContext`/`parseSpawnFanoutContext` retornando `Result[..., string]` e o `of SpawnSubagentsToolName` em `executeAgentNativeTool`. O dispatch monta o plano com `planFanout(..., availableTools = nomes de ctx.tools)` e converte erro de plano em `handledError`; `wait=false` devolve `fanout_id` + ids **antes** da conclusão (supervisor em `mgr.fanouts`, US-004).
- [ ] `core/tooling/native_tool_dispatch.nim`: nome em `AgentNativeTools`; `app/session_bootstrap.nim`: tool em `nativeSessionTools()`; `spawn_subagents` em `SubagentHardDeniedTools` (`domain/subagent_pure.nim`), filho com `startFanout = nil`.
- [ ] `attachSubagentRuntime` liga os dois callbacks. JSON: `fanout_id`, `stop_reason`, `children[]`, `aggregate` (`ok/failed/timed_out/cancelled/total_tokens`); `resultKind` é `trkOperationalError` quando `stopReason != fsrNone`.
- [ ] `tests/app/t_fanout_tool.nim`: parsing feliz, `tasks` vazio, item sem `task`, > 8 tarefas, `wait=false` devolvendo ids com os filhos ainda rodando, e despacho via `executeNativeTool`; `t_native_tools.nim` e `t_session_bootstrap.nim` passam sem edição.

### US-007: Documentar e fechar a missão
**Descrição:** a próxima pessoa entende quando usar fan-out e o que ele não é.

**Critérios:**

- [ ] Criar `docs/topics/subagents.md`: `spawn_subagent` × `spawn_subagents`, ordem determinística, fail-fast/collect-all, teto de plano × teto de runtime, settlement antes de cleanup, `wait=false` só com ids, isolamento e a fronteira com rooms/relay/Kanban; `docs/index.md` lista o tópico em "Topics" (se o arquivo estiver em outro PRD, adicione após o merge).
- [ ] `rg -n "spawn_subagents" src/donkey/domain/more_tools.nim src/donkey/app/native_tools.nim src/donkey/core/tooling/native_tool_dispatch.nim src/donkey/app/session_bootstrap.nim src/donkey/domain/subagent_pure.nim` → **5** pontos de fiação.
- [ ] `rg -n "rooms|relay|kanban" src/donkey/domain/fanout_pure.nim src/donkey/app/subagent_runtime.nim src/donkey/app/native_tools.nim src/donkey/domain/more_tools.nim` vazio (não usar `src/donkey`: `adapters/channel/matrix.nim` casa `/rooms/`).
- [ ] Commit registra que a missão entrega o fan-out, **não** fecha o item 3 da V4 e não recalcula o placar.

## 7. Requisitos funcionais

- **FR-1:** Plano, agregação, stop reason, orçamento e progresso vivem em `domain/fanout_pure.nim`, como `func`, sem chronos/I/O/adapter.
- **FR-2:** O runtime é a única camada que cria paddock, dispara future e cancela; erro de I/O chega como `Result`/status, nunca como exceção.
- **FR-3:** Cada filho tem sessão, histórico, usage, inbox/outbox e paddock próprios; nenhum estado mutável é compartilhado. Paddock só é removido após o future do filho liquidar.
- **FR-4:** Agregado ordenado pelo índice do plano, independente da conclusão; JSON estável com `timed_out`.
- **FR-5:** `fpFailFast` cancela irmãos no primeiro failure; `ssCancelled` nunca é failure nem re-dispara cancelamento.
- **FR-6:** Dois tetos: o de plano (`FanoutAbsoluteMaxAggregateTokens`) recusa pedidos absurdos; o de runtime (`maxAggregateTokens`) cancela o fan-out quando o consumo real estoura.
- **FR-7:** O turno pai recebe no máximo uma linha de progresso por filho concluído e o desfecho por filho no resultado da tool.
- **FR-8:** Stop do processo e `/stop` cancelam todos os filhos e os supervisors detachados, com bound de 2 s.
- **FR-9:** `wait=false` expõe ids imediatamente e não deixa supervisor fora de `mgr.fanouts`/`cancelAll`.
- **FR-10:** Profundidade continua 1 e `spawn_subagent`, `await_subagent`, `list_subagents` e `cancel_subagent` mantêm contrato e testes atuais.

## 8. Não-objetivos

Rooms, relay e Kanban; unificar fan-out com os jobs `task`/`await`/`cancel_job`; persistir/retomar fan-out após restart; compartilhar contexto/memória entre irmãos; worktree git por filho; mudar approval, rede, sandbox ou política de tools do filho; expor fan-out em dashboard/TUI/API. A missão **não** fecha o item 3 da V4 nem move o placar.

## 9. Considerações técnicas

- `NativeCtx` é copiado por valor; o `SubagentUsage` de cada filho é um `ref` novo — nunca o do pai nem o de um irmão.
- `spawn` já valida profundidade, provider assíncrono, paddock e allowlist; `planFanout` valida forma/tools/orçamento e `startFanout` só pré-valida o teto de concorrência.
- Supervisão sem busy-wait: `sleepAsync(100)` por tick, deadline único de `fanoutDeadlineMs(plan)`, `cancelSoon()` + `reap*`, e settlement com `withTimeout` antes de `workspace.remove`.
- Progresso usa o outbox **do pai**, com `streamId` próprio; o outbox do filho continua drenado pelo pai. `fanout_id` = `fan-<epochMs>-<counter>` do primeiro filho.
- `cancelSubagent` muda de comportamento (não remove mais o paddock antes do settlement): se um teste existente depender da remoção síncrona, isso é mudança de comportamento e a história diz isso — não edite asserção para esconder a corrida.

## 10. Métricas de sucesso

- Fan-out de 3 filhos: 0 paddocks órfãos, `#remove == #create`, todo `remove` depois de `settled`, 100% dos ids no agregado, ordem igual à do plano, 3 filhos iniciados antes da primeira resposta (barreira).
- Soma de tokens do agregado = soma exata dos filhos (inclui falhos) e o gatilho de `fsrAggregateBudget` é provado em runtime.
- Suíte verde sem editar testes existentes; baseline = o medido no commit de abertura (registrado, não hardcoded) + testes novos, **0 failed**; `check_boundaries.sh` exit 0.
- Nenhum import novo de `app/`/`adapters/` em `domain/`.

## 11. Questões em aberto

- `wait=false` devolve só ids; o agregado detachado vive em `mgr.fanouts` e nos eventos. Se houver consumidor real, promover um `await_fanout`/`list_fanouts` em outra missão.
- Defaults: `maxAggregateTokens = 256_000` (soma dos 8 filhos default) e `FanoutAbsoluteMaxAggregateTokens = 512_000`; revisar com uso real.
- `fail_fast` default assume que um filho falho invalida o agregado; a política é dado, não código.
[/PRD]
