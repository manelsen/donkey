[PRD]
# PRD: Automação — cron persistido, scheduler e visibilidade operacional

> **Executor:** agente autônomo. Leia este documento inteiro antes de começar.
> Execute as histórias **na ordem**. Cada história termina com os quality gates
> verdes e um commit próprio. Não abra a história seguinte com a anterior vermelha.

## 1. Contexto

Hoje o Donkey agenda por `core/cron.nim` (parse, `matchesCron` e `nextRun` puros, sem fuso nem persistência) e por `app/heartbeat.nim`, cujo `startHeartbeatCron` roda o registry inteiro; `schedule_reminder` é disparo único e apaga o registro no envio. `src/donkey.nim:1899` aceita `DONKEY_HEARTBEAT_CRON`, mas ele agenda o heartbeat inteiro: não há agendamento por usuário/canal, histórico nem próxima execução visível — item 6 da V4 (Automação 48%, recorte "cron com scheduler e retenção"). A missão entrega **cron persistido com semântica de execução explícita**, não um segundo heartbeat.

## 2. Objetivos

1. Spec persistida: expressão cron, fuso, usuário, canal, payload e catch-up.
2. Cálculo puro de janela, ocorrências perdidas e próxima execução.
3. Firing **at-most-once** com marcador durável (fsync) antes do enqueue, retenção e compactação sobrevivendo a restart.
4. Visibilidade read-only (última, próxima, falhas) em CLI e TUI.

## 3. Fora de escopo

- Agendamento distribuído, múltiplos hosts, worker pool, fila externa (Redis/SQS), rooms hospedados ou leader election além do lease de daemon existente.
- Fuso IANA com DST: nesta missão fuso é **offset fixo** `UTC±HH:MM`; cron de 6 campos/segundos, `@daily` e nomes de mês/dia ficam fora.
- Criar schedule por conversa (`schedule_task`) ou pela TUI.
- Retry automático de execução falha; falha é visível, não reexecutada.
- Reescrever `schedule_reminder`/heartbeat sobre o novo scheduler.

## 4. Quality gates

Obrigatórios ao fim de **toda** história:

```bash
bash scripts/check_boundaries.sh
nimble build -y
JOBS=6 bash scripts/run_tests.sh
git diff --check
```

Regras adicionais, sem exceção:

- TDD: escreva o teste, confirme que **falha**, implemente, confirme que passa.
- Lógica pura em `domain/`/`core/` como `func`; adapter só liga; proibido `raise` fora de adapter e I/O falível devolve `Result[T, string]`.
- Nenhum teste novo usa rede, provider real, Docker, `sleep` real ou clock real.
- Nenhum teste existente é editado para "acomodar" a mudança; se precisar mudar, o comportamento mudou e a história deve dizer isso.
- Worktree sujo ao começar: **pare** e registre.

### 4.1 Ciclo de execução — TDD não é opcional

1. Escrever **um** arquivo de teste (ou bloco novo) e rodá-lo sozinho.
2. **Mostrar a falha** no relato: `run_tests.sh` com o erro esperado (módulo ausente, símbolo inexistente ou asserção). Teste que passa antes está errado.
3. Implementar o mínimo, rodar o mesmo teste até verde e então os quality gates completos.
4. Commitar com a evidência vermelho → verde no corpo (duas linhas bastam).

Proibido implementar antes do vermelho, editar teste existente para acomodar comportamento novo e rodar a suíte inteira como primeiro sinal.

### 4.2 Ordem, dependências e paralelização

- Ordem: **001 → 002 → 003 → 004 → 005 → 007 → 006 → 008**. Dependências reais: 004←003, 006←004+005, 007←004 (dados de run), 008←007 (`schedule_view.nim`).
- Overlaps permitidos: **005 em paralelo com 002/003** (arquivos disjuntos) e **007 em paralelo com 004** (só `schedule_view.nim` + `ctl_handler.nim`).
- Um escritor por arquivo: `schedule_pure.nim` (001/002 serial); `ports/scheduler.nim` + `adapters/state/schedule_store.nim` (003); `app/scheduler_runtime.nim` (004); `agent_message.nim` + `orchestrator.nim` (005, com `session_ingress.nim` só leitura); `src/donkey.nim` (006); `ctl_handler.nim` + `schedule_view.nim` (007); `tui/dashboard.nim` + `docs/topics/automation.md` (008).
- `src/donkey.nim` é **compartilhado entre PRDs**: a US-009 do `prd-provider-transport.md` também o edita. Serializar os dois; quem commitar primeiro libera o arquivo. Suíte completa e commits só na sessão principal.

## 5. Dependências e preparação

- **Dependência funcional de `tasks/prd-provider-transport.md`: nenhuma.** Não usa descritores, `compat.nim` nem perfis. Há sobreposição em `src/donkey.nim` (ver §4.2); os demais arquivos são disjuntos. As duas missões não rodam `run_tests.sh` completo ao mesmo tempo.
- Preparação: `git status --short` limpo; `git switch master && git pull --ff-only`; criar `feat/automation-cron`; commit de abertura registra este PRD como fonte de verdade.

## 6. Histórias

### US-001: Spec pura e offset de fuso
**Descrição:** Como mantenedor, quero validar um schedule antes de persistir, com fuso explícito e sem depender de clock.

**Critérios de aceite:**
- [ ] Criar `src/donkey/domain/automation/schedule_pure.nim` com `ScheduleSpec` (`id`, `cronExpr`, `tzOffsetMinutes`, `userId`, `channel`, `payload`, `catchUp`, `enabled`, `createdAtMs`) e `ScheduleCatchUp = scSkip, scOnce`.
- [ ] `parseTzOffset*("UTC-03:00"): Result[int, string]` aceita `UTC±HH:MM` (−840..840) e recusa nome IANA com erro explícito, nunca fallback.
- [ ] `validateScheduleSpec*` recusa id vazio, cron inválido (via `core/cron.parseCronExpr`), offset fora da faixa, `userId`/payload vazios, canal que não parseia para `ChannelKind` e payload > 4 KiB.
- [ ] Teste `tests/domain/automation/t_schedule_pure.nim`: offsets válidos, sinal invertido, minuto 60, IANA, cron de 4/6 campos, canal inválido.

### US-002: Janela, ocorrências perdidas e catch-up
**Descrição:** Como mantenedor, quero saber o que vence entre a última execução e agora, e o que fazer com o atraso.

**Critérios de aceite:**
- [ ] Em `schedule_pure.nim`, `dueInstants*(spec, lastRunMs, nowMs): seq[int64]` e `nextRunAfterMs*(spec, nowMs): Option[int64]`, `func`, sem clock.
- [ ] Janela **`(lastRunMs, nowMs]`** (agora inclusivo); `nextRunAfterMs` é **estritamente > nowMs** (um match em `nowMs` já pertence à janela). `nowMs < lastRunMs` (relógio para trás) → janela vazia, `nextRunAfterMs` a partir de `nowMs`, sem crash.
- [ ] `scSkip`: perdida não gera firing; `scOnce`: no máximo **uma**, a mais recente, por busca para trás limitada ao horizonte — nunca 527k minutos por tick nem replay de backlog.
- [ ] Horizonte de 366 dias; cron que nunca casa (`0 0 30 2 *` parseia) → `none`, sem sentinela; offset é **removido** antes de retornar epoch real (09:00 em `UTC-03:00` = 12:00Z); mudar o offset não retro-dispara.
- [ ] Primeira observação: `lastRunMs` inicial = `createdAtMs` (gravado no `add`), então `scOnce` não dispara no primeiro tick após a criação.
- [ ] Teste `tests/domain/automation/t_schedule_due.nim`: janela vazia, borda `nowMs == ocorrência`, vários matches, virada de dia no offset, rollback, `none`, epoch real.

### US-003: Port e store durável
**Descrição:** Como mantenedor, quero schedules e execuções em disco, com escrita concorrente segura, retenção e compactação, sem `raise` na fronteira.

**Critérios de aceite:**
- [ ] Criar `src/donkey/ports/scheduler.nim` com `ScheduleRecord` (spec + `lastRunAtMs`, `lastStatus`, `lastError`), `ScheduleRunRecord` (`pending|sent|failed`), `ScheduleStorePort` (`loadAll`, `upsert`, `remove`, `markRun`, `loadRuns`) e `hasScheduleStore`; callbacks `{.gcsafe, raises: [].}`.
- [ ] Criar `src/donkey/adapters/state/schedule_store.nim`: `state/schedules.json` com `version`, tmp único `pid-seq`, fsync de arquivo e dir, 0600/0700; `state/schedule_runs.jsonl` append-only newline-framed.
- [ ] **Lost update:** `state/schedules.lock` com flock exclusivo cobre todo load→modify→write (daemon e `ctl`); rename atômico sozinho não basta. Dois `ctl add` concorrentes preservam os dois schedules.
- [ ] `version` futura ou campo desconhecido → `Err`, arquivo preservado e **compactação do runs abortada** (regra `hasForwardIncompatibleEvents`), para rollback não duplicar disparos; `schedules.json` corrompido → `.corrupt-<epoch>` e store vazio.
- [ ] Compactação de runs mantém `pending`, a **última execução de cada schedule** e terminais dentro de `DONKEY_SCHEDULE_RETENTION_DAYS` (default 30); teto de **50** schedules por usuário; toda falha de I/O é `Err`, nunca exceção.
- [ ] Teste `tests/state/t_schedule_store.nim`: round-trip, concorrência de escritores, corrupção, versão futura, retenção com relógio injetado, último run antigo preservado, append durável.

### US-004: Runtime at-most-once e reconciliação
**Descrição:** Como mantenedor, quero que um restart nunca duplique um disparo e que execução interrompida apareça como falha.

**Critérios de aceite:**
- [ ] Criar `src/donkey/app/scheduler_runtime.nim` com `tickScheduler*(store, enqueue, nowMs): Result[int, string]`, recarregando schedules do disco a cada tick; `enabled=false` é ignorado e reabilitar não altera `lastRunMs` (catch-up segue a janela real).
- [ ] Pular se já existe registro de run (`pending`, `sent` ou `failed`) para `(scheduleId, instant)` — `failed` é tentativa consumada e **não** reabre o firing. Gravar `pending` com fsync (arquivo+dir) **antes** do enqueue; se o append falhar, **não enfileirar** e devolver `Err` (fail-closed).
- [ ] `markRun(sent)` com `Err`: o marcador continua `pending` e o próximo tick **pula** (não re-dispara); startup reconcilia para `failed`. Sucesso do enqueue → `sent`; exceção do enqueue → `failed` com a mensagem, **sem retry de firing**.
- [ ] `reconcileInterruptedRuns*` marca `pending` como `failed` ("interrupted by restart") no startup e **não reenfileira**.
- [ ] Testes em `tests/app/t_scheduler_runtime.nim`: fakes (dois ticks, falha de enqueue) **e** store real em dir temporário — grava `pending`, descarta a instância, reinstancia, reconcilia → `failed`, enqueue 0.

### US-005: Enfileirar como tarefa de sessão
**Descrição:** Como usuário, quero que o schedule vire uma tarefa no meu inbox, igual ao heartbeat, e não uma mensagem solta.

**Critérios de aceite:**
- [ ] Adicionar `tkSchedule` em `TaskKind` (`src/donkey/domain/agent_message.nim`).
- [ ] `src/donkey/app/orchestrator.nim` trata `tkSchedule` como tarefa proativa (mesmo gate de onboarding e supressão de progresso de `tkHeartbeat`), sem cair no descarte de `taskKind notin {tkUserMsg, tkHeartbeat}`.
- [ ] Enqueue usa `ensureSessionTask` (`app/session_ingress.nim`, sem alterar assinatura) com `userId`, `channel` (`ChannelKind`) e payload; usuário revogado → `failed`.
- [ ] Teste `tests/app/t_scheduler_ingress.nim`: `taskKind == tkSchedule`, canal/usuário corretos e mensagem não descartada.

### US-006: Fiação no daemon e configuração
**Descrição:** Como operador, quero ligar o scheduler por ambiente, com tick próprio e configurável, sem tocar no heartbeat.

**Critérios de aceite:**
- [ ] `src/donkey.nim` sobe o scheduler em **loop periódico próprio** (`startPeriodicTask(..., intervalSec = tickSec, name = "scheduler")` ou equivalente dedicado), **nunca** registrado no `HeartbeatRegistry` cron; `DONKEY_HEARTBEAT_CRON` não pode silenciar `DONKEY_SCHEDULES_TICK_SEC` (default `60`).
- [ ] `DONKEY_SCHEDULES_ENABLED=1` (default `0`), `DONKEY_SCHEDULE_CATCHUP=skip|once` (default `skip`) e `DONKEY_SCHEDULE_RETENTION_DAYS` (default `30`) são lidos **na borda** (`src/donkey.nim`/`ctl_handler`) e injetados; campo do spec vence e o domínio nunca lê env.
- [ ] Startup roda `reconcileInterruptedRuns` antes do primeiro tick e loga schedules carregados, reconciliados e erros de I/O; falha é logada e não derruba o daemon nem os outros tasks.
- [ ] Teste `tests/app/t_scheduler_wiring.nim` com env controlado: `DONKEY_HEARTBEAT_CRON` presente + tick 5 → intervalo do scheduler continua 5; `enabled=0` não sobe loop. Nenhum processo de daemon.

### US-007: Visão e gestão via `donkey ctl`
**Descrição:** Como operador, quero ver última/próxima execução e falhas, e gerenciar schedules sem reiniciar o daemon.

**Critérios de aceite:**
- [ ] Criar `src/donkey/domain/automation/schedule_view.nim` com `formatScheduleRow*` e `schedulePanelLines*`, puros, exibindo `last_run`, `next_run` (ou `never`), `last_status`, `last_error` e `failures`.
- [ ] `failures` = contagem de runs `failed` **retidos**, fonte `loadRuns`, rotulada `failures (since retention)`; a última execução (mesmo antiga) é sempre preservada pela compactação, então `last_status`/`last_error` nunca somem.
- [ ] `donkey ctl schedule list`, `show <id>`, `add`, `remove`, `enable` e `disable` em `src/donkey/ctl_handler.nim`; `list/show` só leem o store, funcionam com o daemon parado e aceitam `--json`.
- [ ] `add` valida via US-001, recusa id duplicado com erro (nunca upsert silencioso), grava `createdAtMs`/`lastRunAtMs`; id inexistente em `remove/enable/disable` → erro e exit ≠ 0.
- [ ] Teste `tests/domain/automation/t_schedule_view.nim` (formatação/truncagem) e `tests/app/t_ctl_schedule.nim` (list vazio, com runs, add inválido, add duplicado).

### US-008: Painel TUI read-only e documentação
**Descrição:** Como operador, quero ver os schedules no dashboard sem poder alterá-los por lá.

**Critérios de aceite:**
- [ ] `src/donkey/tui/dashboard.nim` renderiza seção "Schedules" com `schedulePanelLines`, somente leitura e tolerante a store ausente/corrompido; `rg -n "schedulePanelLines" src/donkey/tui/dashboard.nim` encontra a chamada.
- [ ] Teste `tests/tui/t_dashboard_schedule.nim` cobre truncagem por altura e estado vazio; nenhum terminal real é aberto.
- [ ] Criar `docs/topics/automation.md` com layout de arquivos, at-most-once/fsync, catch-up (inclusive `enabled=false` e reabilitação), retenção/compactação, offset fixo e o que está fora.
- [ ] Atualizar a ajuda de `src/donkey.nim` com `ctl schedule …` (mesmo dono da US-006, após ela).

## 7. Requisitos funcionais

- **FR-1:** Parse de cron, offset, janela e próxima execução são `func` puros em `domain/automation/`, sem relógio, disco ou env; persistência, enqueue e relógio ficam em `app/` e `adapters/state/`.
- **FR-2:** Ocorrência executada no máximo uma vez, inclusive após crash: `pending` com fsync precede o enqueue; append falho não enfileira.
- **FR-3:** Qualquer marcador existente (`pending|sent|failed`) bloqueia novo firing; `failed` pós-reconciliação também não reabre o disparo.
- **FR-4:** Catch-up é explícito e limitado a uma ocorrência; backlog nunca é reproduzido.
- **FR-5:** Retenção roda no startup e periodicamente, sem apagar a última execução de cada schedule.
- **FR-6:** Toda I/O retorna `Result`; nenhum `raise` cruza port ou app.
- **FR-7:** Visão operacional derivada do store; `list/show` funcionam sem daemon no ar.
- **FR-8:** `schedule_reminder` e heartbeat existentes não mudam de comportamento.

## 8. Não-objetivos

- Garantir exactly-once: o contrato é at-most-once com falha visível; `sent` significa **enfileirado no inbox da sessão**, não entregue no canal — entrega/retry é do delivery ledger.
- At-most-once pressupõe **um** daemon no `state/` (lease); segundo processo concorrente está fora.
- Sem catch-up para `enabled=false` até reabilitar; ao reabilitar, a janela vem do `lastRunMs` inalterado.
- Exceder 50 schedules/usuário ou sincronizar entre instâncias/hosts; fuso IANA/DST, feriados ou "último dia útil".
- Criar schedule por conversa, TUI ou API HTTP.
- Substituir o delivery ledger ou o heartbeat por este store.

## 9. Considerações técnicas

- Reuse `core/cron.nim` como parser/matcher; não duplique campos nem semântica de dia-do-mês/dia-da-semana.
- Converta o offset fixo em `DateTime` UTC deslocado (`utc + offset`) na borda do domínio e **remova o deslocamento** ao devolver epoch; cálculo em UTC, sem `times.local`; offset novo só afeta ocorrências futuras.
- Espelhe `adapters/state/runtime_store.nim` (tmp+fsync+rename, `.corrupt-<epoch>`, newline-framed), mas `pending` do scheduler é **durável** — ao contrário de `runtime_store.recordPending` (`durable=false`), que aceita duplicata.
- Lock exclusivo (`schedules.lock`) serializa load→modify→write de daemon e `ctl`; o runs ledger é append-only e não precisa do lock.
- Nada de `sleep` em teste: injete `nowMs` e o `enqueue`.
- Se um teste de heartbeat/orchestrator precisar mudar na US-005, pare e documente: o requisito é aditivo.

## 10. Métricas de sucesso

- Schedule sobrevive a restart e cada ocorrência aparece **uma** vez no log, inclusive com `pending` interrompido.
- Store real + nova instância: 0 reenfileiramentos; dois `ctl add` concorrentes não perdem schedule.
- `donkey ctl schedule list` mostra `last_run`, `next_run`, `last_status` e `failures` sem daemon; store corrompido não impede o daemon de subir.
- Suíte total verde (baseline **242 passed, 0 failed**), sem edição de testes existentes; `check_boundaries.sh` exit 0.
- Nenhum import de `adapters/*` em `domain/`/`core/`; nenhum `raise` novo fora de adapter.

## 11. Questões em aberto

- Fuso IANA: aceitar nome e resolver com tzdb do sistema, ou manter offset fixo? Nesta missão: offset fixo, nome recusado.
- Materializar `nextRunAtMs` no `schedules.json` ou derivar na leitura? Preferir derivar; materializar só se a TUI ficar lenta.
- Schedule de usuário revogado: marcar `failed` com "user revoked" em vez de enfileirar (regra inicial).
- Compactação em thread própria (como o ledger) ou no tick? Começar no tick.
[/PRD]
