[PRD]
# PRD: Fan-out paralelo de subagentes e observabilidade do turno pai

> **Executor:** agente autônomo. Leia o documento inteiro antes de começar.
> Ordem única de execução: **US-001 → US-002 → US-003 → US-006 → US-005 → US-004 →
> US-007**. US-001/US-002 já estão entregues; a missão continua na US-003. Cada história
> termina com os gates verdes e um commit próprio; não abra a seguinte com a anterior vermelha.

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

O `hermes-agent` cobre o domínio com rooms/relay/Kanban; **nada disso entra**. O recorte é o
item 3 da seção 6 da V4 — fan-out paralelo — mais a observabilidade mínima para confiar no
agregado. Esta missão **não fecha** o item 3 da V4 (rooms/relay ficam fora) e **não move** o
placar; ela entrega o fan-out.

**Estado:** US-001 e US-002 já estão em `src/donkey/domain/subagent_pure.nim`, com testes em
`tests/domain/t_fanout_plan.nim` (os critérios dessas duas histórias descrevem a API exportada).
O runtime (`app/subagent_runtime.nim`) e a tool ainda não existem.

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
entre irmãos; custo em USD (não preenchido hoje); dashboard/TUI novos.

## 4. Quality gates

Obrigatórios ao fim de **toda** história:

```bash
bash scripts/check_boundaries.sh
nimble build -y
JOBS=6 bash scripts/run_tests.sh
git diff --check
```

Adicional em US-003, US-004 e US-005 (concorrência): `bash scripts/run_stress_tests.sh`.
Regras, sem exceção: TDD com o vermelho antes da implementação; lógica pura em `domain/` como
`func`; `raise` proibido fora de adapter; I/O falível devolve `Result[T, string]`; teste novo
sem rede/provider real/Docker/sleep; teste existente não é editado para "acomodar". Por
história: rodar o teste sozinho, mostrar a falha, implementar até verde, gates e commit com a
evidência vermelho → verde.

### 4.1 Escritores e paralelização

- `domain/subagent_pure.nim` (puro): **um escritor**. Ordem: US-001 → US-002 (entregues) →
  US-006 (`SubagentHardDeniedTools`) → US-005 (`SubagentInfo.fanoutId`).
- `app/subagent_runtime.nim`: US-003 → US-006 → US-005 → US-004, em sequência.
- **Colisões:** `app/session_bootstrap.nim` é de `tasks/prd-ferramentas.md` US-003 (já
  mergeada em `418cf193`) e do `tasks/prd-provider-transport.md` US-001 (pendente) — escreva
  nele só depois do provider. `domain/more_tools.nim`, `app/native_tools.nim` e
  `core/tooling/native_tool_dispatch.nim` são **só desta missão**.
- `mgr.fanouts` é bookkeeping para cancelamento; só filhos **vivos** contam em `maxConcurrent`.
- Cada subagente declara os arquivos que possui; testes de histórias diferentes podem ser
  escritos em paralelo (cada história é dona do seu arquivo).
- Suíte completa e commits são **sequenciais na sessão principal** (binários colidem).

## 5. Preparação (antes da US-003)

1. `git status --short`. Pare **somente** se um arquivo desta missão estiver sujo:
   `domain/subagent_pure.nim`, `app/subagent_runtime.nim`, `domain/more_tools.nim`,
   `app/native_tools.nim`, `core/tooling/native_tool_dispatch.nim`, `core/agent_events.nim`,
   `app/session_bootstrap.nim`, `docs/topics/subagents.md`. Sujeira de provider/ferramentas não bloqueia; nunca use stash, reset ou checkout.
2. `git fetch && git switch master && git pull --ff-only`. Ferramentas está mergeada
   (`418cf193`); a missão de provider pode estar pendente no worktree — trabalhe sobre ela,
   não reverta.
3. Branch `feat/subagent-fanout`; commit de abertura aponta este PRD como fonte de verdade e
   registra o baseline medido hoje (`JOBS=6 bash scripts/run_tests.sh`, inclui `t_fanout_plan.nim`).
4. **Dependência de `tasks/prd-provider-transport.md`:** sem dependência de API; só processo
   (gates, baseline) e o arquivo `session_bootstrap.nim` (ver §4.1).

## 6. Histórias

### US-001: Plano puro de fan-out e orçamento agregado
**Descrição:** validar o conjunto (forma, tools e orçamento) antes de criar qualquer filho.

**Critérios (entregues):**

- [x] Em `src/donkey/domain/subagent_pure.nim`: `FanoutRequest` (+ alias `FanoutTask`), `FanoutLimits` (`maxChildren`, `maxAggregateTokens`, `maxAggregateDurationMs`), `FanoutPlan` (`tasks`, `limits` normalizado, `plannedTokens`, `len`), `defaultFanoutLimits()` = 8 filhos / 256_000 tokens / 120_000 ms, `FanoutMaxChildren* = 8`, `FanoutAbsoluteMaxAggregateTokens* = 512_000`, `FanoutDefaultAggregateTokens* = 256_000`.
- [x] `planFanout*(tasks, limits, availableTools): Result[FanoutPlan, string]` recusa 0 tarefas; `maxChildren` > 8 ou tarefas > `maxChildren`; `maxAggregateTokens` <= 0 ou > 512_000; `maxAggregateDurationMs` <= 0 ou > `SubagentMaxDurationMs` (**600 s**); valida o filho com `subagentRequestError(SubagentRequest(task, context, tools), 0)`; tool fora de `availableTools`; `plannedTokens` (soma dos `maxTokens` clampados) > 512_000. Limites efetivos ficam normalizados no plano.
- [x] `tests/domain/t_fanout_plan.nim` cobre 1/8/9 tarefas, tarefa vazia, tool proibida e indisponível, budget zero, duração zero, budget acima do absoluto, soma acima do teto e determinismo; `t_subagent_pure.nim` sem edição. `rg -n "chronos|adapters/|app/|httpclient" src/donkey/domain/subagent_pure.nim` vazio; `check_boundaries.sh` exit 0.

### US-002: Agregação determinística, sinal e política de parada
**Descrição:** a ordem de conclusão não muda o resultado; stop reason e cancelamento são puros.

**Critérios (entregues):**

- [x] `FanoutOutcome` (+ alias `FanoutChildOutcome`) e `aggregateFanout*(plan, outcomes, fanoutId, policy, signal: FanoutSignal): FanoutAggregate`: filhos indexados `0..N-1`; ausente vira `ssQueued`; índice fora do plano ou duplicado é ignorado (primeiro vence); `totalTokens` soma **todos** (inclusive falhos/cancelados); `totalDurationMs` soma as durações por filho (wall-clock é do runtime).
- [x] `stopReason` = precedência `spawnFailed` > `stopRequested` > `budgetExceeded` > primeiro failure por índice (`ssFailed` → `fsrChildFailed`; `ssTimedOut` → `fsrChildTimedOut`), ignorando `ssCancelled` e `cancelledBySibling`. `fanoutShouldCancelSiblings` só é `true` em `fpFailFast` e nunca reage a cancelado.
- [x] `fanoutBudgetDecision*(totalTokens, limits)`: `>=` teto = `bdTokensExceeded`; `maxAggregateTokens == 0` significa o default de 256_000 (caller detached sem budget). `planFanout`, ao contrário, exige budget > 0.
- [x] `fanoutProgressDue*(lastMs, nowMs, intervalMs = 1_000)`: `intervalMs <= 0` → `true`; `nowMs < lastMs` → `false`; senão `nowMs - lastMs >= intervalMs`.
- [x] `tests/domain/t_fanout_plan.nim` cobre ordem invertida, cancelado que não vira stop reason, timeout, precedência, 10+15 > 20, default de 256k e throttle. `t_subagent_pure.nim` sem edição.

### US-003: Runtime `startFanout`/`spawnFanout`
**Descrição:** disparar N filhos concorrentes, expor os ids e devolver um agregado determinístico.

**Critérios:**

- [ ] `FanoutHandle` (`fanoutId`, `childIds`) e `FanoutStart` (`handle`, `failedIndex`, `error`) em `app/subagent_runtime.nim`. `startFanout*(mgr; parent: NativeCtx; plan: FanoutPlan; policy: FanoutPolicy): Future[FanoutStart]` faz **sequencial** `await mgr.spawn` por tarefa: `spawn` é `{.async.}` sem `await` interno, então os N filhos começam juntos. Não usar `awaitSubagent` por filho.
- [ ] **Falha parcial:** aborta o plano; `FanoutStart.error` traz a mensagem, `failedIndex` o índice e `handle.childIds` **os ids já criados e cancelados**. Cada um passa por `settleChild` (≤ 2 s) e `finalizeChild`. `spawnFanout` converte em agregado com `signal.spawnFailed = true` e `children` derivados de `handle.childIds`. Teste: port de workspace falhando no 2º `create`, 3 tarefas, `create`/`remove` casados, nenhum filho vivo.
- [ ] **Dono único da remoção:** `finalizeChild(mgr, rt)` é a única função que chama `workspace.remove`, e só quando `childSettled(rt)` = status terminal (`notin {ssQueued, ssRunning}`) **e** `future.finished()`. `runChild` finally não remove mais; `settleChild` cancela, espera `withTimeout(rt.future, 2_000)` e chama `finalizeChild`; timeout não remove. `cancelSubagent` deixa de remover o paddock: mudança de comportamento declarada, sem editar asserção para esconder a corrida.
- [ ] **Cleanup é reagendado, não só logado:** um `settleChild` que vence em 2 s deixa o paddock no lugar porque o future do filho ainda não terminou; sem um segundo caminho de remoção ele vira órfão permanente. O término **tardio** do future do filho (callback `addCallback` e a varredura periódica de retenção) precisa chamar `finalizeChild` de novo, depois de reavaliar `childSettled`; a remoção vale para o filho de fan-out e para o avulso, com e sem supervisor, e o log de órfão continua existindo só como diagnóstico. Teste não-vacuoso: filho cujo future só termina depois do prazo de 2 s termina com `#remove == #create` e nenhum diretório em `subagents/`, sem depender de `/stop` nem do shutdown.
- [ ] Teste não-vacuoso: port espião grava `create:<id>` e, no `remove`, o resultado de `childSettled(mgr, id)`; exige `settled=true` e `#remove == #create`.
- [ ] `spawnFanout = startFanout + awaitFanout*(mgr; fanoutId; stopGeneration; userId; userInterrupt): Future[FanoutAggregate]`. `FanoutState` em `mgr.fanouts: Table[string, FanoutState]` **nos dois modos** (bookkeeping; não ocupa slot). Deadline = `plan.limits.maxAggregateDurationMs` (já ≤ 600 s).
- [ ] **Captura na conclusão:** o supervisor grava o `FanoutOutcome` de cada filho em `FanoutState.outcomes` quando ele termina; `awaitFanout` agrega desse snapshot, nunca de `mgr.children` (a retenção 64 pode podar um filho não lido).
- [ ] Cada filho mantém `SessionState`, `ConversationHistory`, `SubagentUsage`, inbox/outbox e paddock próprios; o `ref` de usage é criado por filho. Se `running + plan.len > mgr.maxConcurrent`, falha antes de criar paddock (`running` = filhos vivos, inclui os de fan-out detachado).
- [ ] `fpFailFast`: no primeiro failure, cancela irmãos via `cancelSubagent`, marca `cancelledBySibling` e para — teste: 2º filho `ssFailed`, 1º/3º `ssCancelled` + `cancelledBySibling`, stop reason `fsrChildFailed`.
- [ ] Barreira (não sleep): 3 filhos com `parent.asyncCompleteFn` (o `completeFn` síncrono bloquearia a thread e daria deadlock, não timeout) esperando `contador == 3`; `maxDurationMs ≥ 2_000`; timeout da barreira 1,5 s. `paddockDirFor` distinto e ordem do agregado igual à do plano.

### US-006: Tool `spawn_subagents`
**Descrição:** expressar o fan-out em uma chamada, com ids imediatos quando `wait=false` e agregado quando `wait=true`.

**Critérios:**

- [ ] `src/donkey/domain/more_tools.nim`: `SpawnSubagentsToolName* = "spawn_subagents"`, schema com `tasks` (objetos com `task`, `context`, `tools`, `max_tool_calls`, `max_tokens`, `max_duration_sec`), `fail_fast` e `wait` (default `true`).
- [ ] `native_tools.nim`: `StartFanoutFn*`/`AwaitFanoutFn*` em `NativeCtx`, `SpawnFanoutContext`/`parseSpawnFanoutContext` retornando `Result[..., string]` e o `of SpawnSubagentsToolName` em `executeAgentNativeTool`. O dispatch monta o plano com `planFanout(..., availableTools = nomes de ctx.tools)` e converte erro de plano em `handledError`.
- [ ] `wait=false` usa **US-003**: devolve `fanout_id` + `childIds` antes da conclusão (supervisor já registrado em `mgr.fanouts`); `/stop` e shutdown sobre esse supervisor são a US-004.
- [ ] `core/tooling/native_tool_dispatch.nim`: nome em `AgentNativeTools`; `app/session_bootstrap.nim`: tool em `nativeSessionTools()`; `spawn_subagents` em `SubagentHardDeniedTools` (`domain/subagent_pure.nim`), filho com `startFanout = nil`.
- [ ] `attachSubagentRuntime` liga os dois callbacks. JSON: `fanout_id`, `stop_reason`, `children[]`, `aggregate` (`ok/failed/timed_out/cancelled/total_tokens`); `resultKind` é `trkOperationalError` quando `stopReason != fsrNone`.
- [ ] `tests/app/t_fanout_tool.nim`: parsing feliz, `tasks` vazio, item sem `task`, > 8 tarefas, `wait=false` devolvendo ids com os filhos ainda rodando, e despacho via `executeNativeTool`; `t_native_tools.nim` e `t_session_bootstrap.nim` passam sem edição.

### US-005: Observabilidade no turno pai
**Descrição:** ver o fan-out progredir e saber quanto custou em tokens, sem esperar o último filho em silêncio.

**Critérios:**

- [ ] `src/donkey/core/agent_events.nim`: `aekFanoutStart`/`aekFanoutDone` ("fanout_start"/"fanout_done", dois kinds) e campo `fanoutId*: string` (vazio fora de fan-out); `kindLabel`/`toJson` incluem `fanoutId` só quando não vazio.
- [ ] `subagent_runtime.nim` emite `fanout <id> start children=N` e `fanout <id> done ok=.. failed=.. timed_out=.. cancelled=.. tokens=.. reason=..`; eventos de filho herdam o `fanoutId`.
- [ ] Progresso: no máximo **um** `OutboundMessage(isPartial=true)` por filho concluído, com `fanoutProgressDue` (US-002) e `lastProgressMs` no `FanoutState`; texto de uma linha montado no runtime a partir dos contadores — sem helper puro novo e sem clock novo em `NativeCtx`.
- [ ] `SubagentInfo` ganha `fanoutId*: string`; `list_subagents` o expõe e `SubagentInfo.toJson` inclui `fanout_id` só quando não vazio, sem alterar os outros campos.
- [ ] Tokens exibidos no done = `aggregate.totalTokens` (soma da US-002), nunca recalculados só sobre vivos.
- [ ] `tests/core/t_fanout_events.nim` (kinds, render, `fanoutId` vazio) e `tests/app/t_fanout_observe.nim` (throttle, agregado, listagem); `t_agent_events.nim` passa sem edição.

### US-004: Stop, teto agregado em runtime e shutdown
**Descrição:** `/stop`, estouro do teto e shutdown derrubam o fan-out inteiro sem órfãos nem futures pendentes.

**Critérios:**

- [ ] O supervisor (de `spawnFanout` ou detachado) checa `isSessionStopRequested`/`isUserStoppedSince` a cada 100 ms, sinaliza `stopRequested`, cancela os filhos vivos e devolve `fsrSessionStop` com parciais.
- [ ] **Teto de runtime:** no tick **e** na conclusão de cada filho, soma os tokens de **todos** os filhos do fan-out — snapshots dos finalizados + vivos — e chama `fanoutBudgetDecision(total, plan.limits)`. Em `bdTokensExceeded` sinaliza `budgetExceeded`, cancela todos e devolve `fsrAggregateBudget`. Teste: teto 20, filho A termina com 15, B com 10 → total 25, C é cancelado e o reason é `fsrAggregateBudget` (prova que finalizado continua contando).
- [ ] `cancelAll` percorre `mgr.children` **e** `mgr.fanouts`, cancela supervisors detachados, e só chama `finalizeChild` (US-003, após `childSettled`) depois do settlement/reap; espera ≤ 2 s. `tests/app/t_subagent_fanout_stop.nim`: 8 filhos, stop e shutdown no meio, `subagents/` vazio, zero futures pendentes, `removes == creates`.
- [ ] `cancel_subagent` de um irmão derruba os demais com `fpFailFast` e não os derruba com `fpCollectAll` (documentado na US-007).

### US-007: Documentar e fechar a missão
**Descrição:** a próxima pessoa entende quando usar fan-out e o que ele não é.

**Critérios:**

- [ ] Criar `docs/topics/subagents.md`: `spawn_subagent` × `spawn_subagents`, ordem determinística, fail-fast/collect-all, teto de plano × teto de runtime (e zero = 256k em `fanoutBudgetDecision`), duração máxima 600 s, settlement antes de cleanup, `wait=false` só com ids, isolamento e a fronteira com rooms/relay/Kanban; `docs/index.md` lista o tópico em "Topics" (se estiver em outro PRD, adicione após o merge).
- [ ] `rg -l "spawn_subagents|SpawnSubagentsToolName" src/donkey` → **5 arquivos**: `more_tools.nim`, `native_tools.nim`, `native_tool_dispatch.nim`, `session_bootstrap.nim`, `subagent_pure.nim` (3 literais + 2 usos da constante).
- [ ] `rg -n "rooms|relay|kanban" src/donkey/domain/subagent_pure.nim src/donkey/app/subagent_runtime.nim src/donkey/app/native_tools.nim src/donkey/domain/more_tools.nim` vazio (não usar `src/donkey`: `adapters/channel/matrix.nim` casa `/rooms/`).
- [ ] Commit registra que a missão entrega o fan-out, **não** fecha o item 3 da V4 e não recalcula o placar.

## 7. Requisitos funcionais

- **FR-1:** Plano, agregação, stop reason, orçamento e progresso vivem em `domain/subagent_pure.nim`, como `func`, sem chronos/I/O/adapter.
- **FR-2:** O runtime é a única camada que cria paddock, dispara future e cancela; erro de I/O chega como `Result`/status, nunca como exceção.
- **FR-3:** Cada filho tem sessão, histórico, usage, inbox/outbox e paddock próprios; nenhum
  estado mutável é compartilhado. Paddock só é removido após `childSettled`, por um único dono
  (`finalizeChild`), e um settlement que vence **não** encerra a obrigação: o término tardio do
  future do filho reagenda a remoção.
- **FR-4:** Agregado ordenado pelo índice do plano; índice inválido é ignorado, ausente é `ssQueued`; snapshot na conclusão.
- **FR-5:** `fpFailFast` cancela irmãos no primeiro failure; `ssCancelled` nunca é failure nem re-dispara cancelamento.
- **FR-6:** Dois tetos: plano (`FanoutAbsoluteMaxAggregateTokens`, 512k) recusa pedidos absurdos; runtime (`maxAggregateTokens`) cancela pelo consumo real somado de todos os filhos.
- **FR-7:** O turno pai recebe no máximo uma linha de progresso por filho concluído e o desfecho por filho no resultado da tool.
- **FR-8:** Stop do processo e `/stop` cancelam todos os filhos e os supervisors detachados, com bound de 2 s.
- **FR-9:** `wait=false` expõe ids imediatamente e não deixa supervisor fora de `mgr.fanouts`/`cancelAll`.
- **FR-10:** Profundidade continua 1 e `spawn_subagent`, `await_subagent`, `list_subagents` e `cancel_subagent` mantêm contrato e testes atuais.

## 8. Não-objetivos

Rooms, relay e Kanban; unificar fan-out com os jobs `task`/`await`/`cancel_job`; persistir/retomar fan-out após restart; compartilhar contexto/memória entre irmãos; worktree git por filho; mudar approval, rede, sandbox ou política de tools do filho; expor fan-out em dashboard/TUI/API. A missão **não** fecha o item 3 da V4 nem move o placar.

## 9. Considerações técnicas

- `NativeCtx` é copiado por valor; o `SubagentUsage` de cada filho é um `ref` novo — nunca o do pai nem o de um irmão.
- `plan.limits` já vem normalizado e carrega o teto de runtime e a duração máxima (≤ 600 s); o supervisor usa essa duração como deadline. `fanoutBudgetDecision` trata `0` como 256k, mas `planFanout` exige budget > 0.
- Supervisão sem busy-wait: `sleepAsync(100)` por tick, `cancelSoon()` + `reap*`, settlement com `withTimeout` e remoção só por `finalizeChild`; o timeout de settlement **não** descarta a remoção, ele a reagenda para o término tardio do future (callback e varredura de retenção).
- Progresso usa o outbox **do pai**, com `streamId` próprio; o outbox do filho continua drenado pelo pai. `fanout_id` = `fan-<epochMs>-<counter>` do primeiro filho.
- `cancelSubagent` muda de comportamento (não remove mais o paddock): se um teste existente depender da remoção síncrona, isso é mudança de comportamento e a história diz isso.

## 10. Métricas de sucesso

- Fan-out de 3 filhos: 0 paddocks órfãos, `#remove == #create`, todo `remove` com `childSettled=true`, 100% dos ids no agregado, ordem igual à do plano, 3 filhos iniciados antes da primeira resposta (barreira).
- Agregado: `totalTokens` = soma exata de todos os filhos (inclui falhos/cancelados) e `totalDurationMs` = soma das durações; o gatilho de `fsrAggregateBudget` é provado em runtime com um filho já finalizado.
- Suíte verde sem editar testes existentes; baseline medido no commit de abertura (inclui
  `t_fanout_plan.nim`) + testes novos, **0 failed**; `check_boundaries.sh` exit 0; nenhum import
  novo de `app/`/`adapters/` em `domain/`.

## 11. Questões em aberto

- `wait=false` devolve só ids; o agregado detachado vive em `mgr.fanouts` e nos eventos. Se houver consumidor real, promover `await_fanout`/`list_fanouts` em outra missão.
- `defaultFanoutLimits()` = 8 / 256k / 120 s; teto absoluto de duração em 600 s. Revisar se 120 s é apertado para 8 filhos.
- `fail_fast` default assume que um filho falho invalida o agregado; a política é dado, não código.
[/PRD]
