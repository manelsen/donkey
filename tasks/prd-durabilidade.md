[PRD]
# PRD: Retomada transacional de turno

> **Executor:** agente autônomo. Leia o documento inteiro antes de começar.
> Execute as histórias **na ordem**; cada uma termina com os quality gates verdes
> e um commit próprio. Não abra a seguinte com a anterior vermelha.

## 1. Contexto

A V4 mediu Durabilidade em 62% (WAL, lease, reconciliação de entregas). Falta o
**turno**: só a entrega tem registro. A ordem real não é linear — `finalizeNormalTurn`
apenas **enfileira** (`app/tool_loop_runtime.nim:616`); o drainer envia depois
(`src/donkey.nim:1456`); a memória é gravada **antes** de a entrega ser confirmada
(`app/orchestrator.nim:502-513`). Entrega e memória são ramos independentes.

- `msg.id` é `userId-seq` (`app/session_ingress.nim:146`), não o id do canal; o payload
  do ator só leva texto/mídia (`app/session_bootstrap.nim:352`).
- Streaming publica parciais antes de existir resposta final (`tool_loop_runtime.nim:134`).
- Transcript é salvo depois de memória/entrega (`orchestrator.nim:632`).
- `deliveryId` inclui timestamp (`app/outbound_runtime.nim:19`); `recordPending` é upsert
  (`runtime_store.nim:771`), então “mesmo id” não impede dois envios.

## 2. Objetivos

1. Diário append-only em `state/turn_journal.jsonl`, escrito antes/depois de cada efeito.
2. Máquina de estados pura com **ramos independentes** de entrega, memória e transcript.
3. Idempotência real: no máximo uma resposta final e uma memória por turno, com limite
   de tentativas e estado terminal.
4. Política explícita de recuperação visível, com fail-closed antes do efeito.
5. Fiação no ingress, no drainer e no startup, com relatório no log.

## 3. Fora de escopo

- Transações distribuídas, consenso e failover multi-host (um host, um lease).
- Reescrever SQLite/WAL, o lease ou o delivery ledger.
- Exactly-once de inbound no canal; o diário apenas descarta reentrega do mesmo
  `messageId`.
- Reexecutar tools externas (shell, HTTP, git) ou reproduzir anexos.
- Mudar formato de `MEMORY.md`, transcript, UI, dashboard ou canais.

## 4. Quality gates

Obrigatórios ao fim de **toda** história:

```bash
bash scripts/check_boundaries.sh
nimble build -y
JOBS=6 bash scripts/run_tests.sh
git diff --check
```

Sem exceção: TDD (teste falha antes da implementação); lógica pura em `domain/`/`core/`
como `func`; proibido `raise` fora de adapter e I/O falível devolve `Result[T, string]`;
nenhum teste novo usa rede, provider real ou Docker; nenhum teste existente é editado
para “acomodar” (bloco novo é permitido — se precisar mudar, o comportamento mudou e a
história diz isso). **Worktree sujo em missão paralela:** pare apenas se a alteração for
em arquivo que **você** possui; o `quirks.nim` removido por outro dono não bloqueia.
Nunca use stash/reset/checkout sobre trabalho alheio.

**Ciclo TDD:** um teste, rodado sozinho → falha mostrada no relato (módulo/símbolo
ausente ou asserção) → implementação mínima → verde → gates completos → commit com o
vermelho → verde no corpo. Proibido implementar antes do vermelho.

**Paralelização:** ordem obrigatória `001→002→003→004→004b→005→006→007→008`. Só
**US-006 corre em paralelo com US-005, depois da US-004b**. US-003 não é paralela a
US-005. Um escritor por arquivo; suíte completa e commits são sequenciais.

## 5. Preparação

1. `git status --short`; pare só se houver alteração nos arquivos que você possui.
2. `git switch master && git pull --ff-only`; criar `feat/turn-journal`.
3. Commit de abertura registra a contagem de testes do dia (V4: 242 passed).
4. **Ownership compartilhado:** esta missão edita `src/donkey.nim`, `app/outbound_runtime.nim`,
   `domain/message.nim`, `app/tool_loop_runtime.nim`, `app/orchestrator.nim`,
   `domain/agent_message.nim` e `app/session_ingress.nim`. Também editam esses arquivos:
   `prd-provider-transport` (US-009, `src/donkey.nim`), `prd-canais` (US-005/006,
   `src/donkey.nim` e `outbound_runtime.nim`), `prd-interfaces` (US-002/003,
   `src/donkey.nim`, `domain/message.nim` e `tool_loop_runtime.nim`), `prd-automacao`
   (US-005/006, `orchestrator.nim`, `agent_message.nim` e `src/donkey.nim`; lê
   `session_ingress.nim`). Qualquer um desses arquivos tem **um escritor por vez**; a
   missão de durabilidade entra depois de quem já o possui e espera a liberação, sem
   rebase de trabalho alheio.

## 6. Histórias

### US-001: Máquina de estados do diário
**Descrição:** Como mantenedor, quero decisões puras e totais por ramo (entrega, memória, transcript).
**Critérios de aceite:**
- [ ] `src/donkey/domain/session/turn_journal_pure.nim` com `TurnPhase` (`tpsAccepted`, `tpsReplyReady`, `tpsCommitted`, `tpsAbandoned`), `ReplyDelivery` (`rdsNone`, `rdsQueued`, `rdsAttempted`, `rdsSent`, `rdsFailed`), `ReplySource` (`rsBuffered`, `rsStreamed`), `MemoryWrite` (`mwsNone`, `mwsPending`, `mwsWritten`, `mwsSkipped`, `mwsLost`), `TranscriptWrite` (`twsNone`, `twsPending`, `twsSaved`, `twsLost`), `TurnEvent`.
- [ ] Schema fechado de `TurnEntry`: `turnId`, `userId`, `channel`, `chatId`, `channelMessageId`, `taskKind`, `inboundText`, `mediaUrls`, `replyText`, `replyHash`, `memoryHash`, `deliveryId`, `ownerEpochMs`, `modelReplays`, `notices`, `attempts` (passes de recuperação), `createdAtMs`.
- [ ] `turnIdFor(userId, channel, channelMessageId, chatId, text)` usa o id do canal e cai para `chatId:channelId:hash(text)` só quando ele é vazio; `applyTurnEvent` avança cada ramo monotonicamente (`Option[TurnEntry]`); `resumePlan(entry): TurnResumePlan` (`replayModel`, `enqueueReply`, `reconcileDelivery`, `markLost`, `emitNotice`, `abandon`) é total sobre o produto cartesiano dos enums.
- [ ] `recoveryNoticeText(entry, channel)` só para entrega tentada/abandonada; `tests/domain/session/t_turn_journal_pure.nim` cobre todas as combinações, transições ilegais, reentrega e limite de tentativas.

### US-002: Adapter append-only do diário
**Descrição:** Como mantenedor, quero que o diário sobreviva ao restart sem duplicar fsync.
**Critérios de aceite:**
- [ ] Extrair `atomicWriteText`, `appendJsonLine`, `syncDir` e permissões 0600/0700 de `adapters/state/runtime_store.nim` para `adapters/state/durable_file.nim`, sem mudar a API pública de `runtime_store`.
- [ ] `adapters/state/turn_journal.nim` com `TurnJournalStore` (`append`, `loadAll`, `loadByInbound`, `compact(nowMs)`) e `ports/turn_journal.nim` com `TurnJournalPort`; append `"\n<json>\n"` com fsync por evento; linha truncada ignorada; compaction mantém ativos + terminais de 7 dias e não compacta diante de campo desconhecido.
- [ ] `tests/state/t_turn_journal.nim`: restart por store novo, linha truncada, permissões 0600/0700, **redação** de `Bearer`/`sk-`/`token=`, retenção e evento futuro; `tests/app/t_durability.nim` verde sem edição.

### US-003: Planejador de recuperação
**Descrição:** Como mantenedor, quero transformar o diário em plano de ações sem enviar nada.
**Critérios de aceite:**
- [ ] `src/donkey/app/turn_recovery.nim` com `recoverPendingTurns(port, nowMs): Result[TurnRecoveryReport, string]`, aplicando `resumePlan` e gravando desfechos (`tevDeliveryFailed`, `tevMemoryLost`, `tevTranscriptLost`, `tevAbandoned`) sem reenviar.
- [ ] Relatório expõe `(turnId, replayModel, enqueueReply, reconcileDelivery, markLost, notice, abandon)` e contadores de duplicata/perda; a recuperação **nunca** chama `safeAppendMemory` (memória só é escrita pelo ator; `enqueueReply` com `mwsNone` marca `mwsLost`).
- [ ] `tests/app/t_turn_recovery.nim`: por janela da seção 9, grava o diário em `$TMPDIR`, abre store novo, roda a recuperação e confere plano/eventos; reentrega `tpsCommitted` vira no-op.

### US-004: Diário no ingress e no ator
**Descrição:** Como mantenedor, quero journalizar antes da fila e antes da resposta, para não perder turno em espera.
**Critérios de aceite:**
- [ ] `app/session_ingress.nim::startSessionIngress` calcula `channelMessageId = msg.messageId` (fallback `chatId:channelId:hash(text)`), `turnId`, consulta `loadByInbound` e **descarta** reentrega de turno `tpsCommitted`; antes de `inbox.addLastNoWait`, grava `tevInboundAccepted` com texto/mídia e `attempts=1`. Append `Err` é **fail-closed**: não enfileira, loga e envia uma única mensagem de falha.
- [ ] `AgentMessage` ganha `turnId*: string` e `channelMessageId*: string`, preenchidos por `buildSessionTaskMsg`/`newTaskMsg`; `startSessionIngress`/`ensureSessionTask` aceitam `turnId` opcional para replay; o ator não depende de `msg.id`.
- [ ] `app/tool_loop_runtime.nim` grava `tevStreamStarted` antes da primeira parcial e `streamToOutbox` recebe `turnId`; `OutboundMessage` ganha `turnId*`/`deliveryId*` aditivos. `app/orchestrator.nim` grava `tevReplyReady` (`replyText`, `replyHash`, `memoryHash`, `rsBuffered|rsStreamed`) antes de `finalizeNormalTurn` e `tevReplyQueued` para o final bufferizado; streamed não usa `queued` (o drainer cobre attempted). Falha antes do efeito = fail-closed; `tkHeartbeat`/controle usam `msg.id` como `turnId`, **não** deduplicam e não guardam texto; só `tkUserMsg` consulta `loadByInbound`.
- [ ] `tests/app/t_turn_journal_ingress.nim`: reentrega do mesmo `messageId` gera um turno; crash com a mensagem na fila é recuperável; port falho não enfileira nem chama provider; `tests/app/t_orchestrator*.nim` verdes sem edição.

### US-004b: Diário no drainer (dono de `delivered`/`failed`)
**Descrição:** Como mantenedor, quero que quem envia seja quem confirma, para que a fase reflita o ack real.
**Critérios de aceite:**
- [ ] `app/outbound_runtime.nim::sendImmediateOutbound` recebe `TurnJournalPort` opcional e grava `tevDeliveryAttempted` (com `ownerEpochMs` do processo) antes de `port.send`, `tevDelivered` no `ok` e `tevDeliveryFailed` no `err`; `routeOutbound` e `src/donkey.nim::drainGlobalOutbox` passam o port.
- [ ] Só a resposta final (bufferizada em `finalizeNormalTurn` ou streamed em `streamToOutbox`) leva `deliveryId = turnId & "-reply"`; progresso/parciais levam `deliveryId = turnId & "-progress-<n>"` e **não** geram evento de resposta. Port ausente = comportamento atual (porta nil).
- [ ] `tests/app/t_turn_delivery_journal.nim`: fake channel + fake journal; `ok` grava `rdsSent` uma vez, `err` grava `rdsFailed`, progresso não aparece como entrega e o total de `port.send` é 1 por chamada.

### US-005: Uma única resposta final por turno
**Descrição:** Como mantenedor, quero que a retomada nunca duplique a resposta, nem após crash no envio.
**Critérios de aceite:**
- [ ] `outbound_runtime.newDeliveryId` usa `OutboundMessage.deliveryId` quando preenchido e mantém o esquema atual quando vazio.
- [ ] O drainer consulta o snapshot do startup **antes** de gravar `tevDeliveryAttempted`; se `rdsAttempted` pertence a outro `ownerEpochMs`, **pula** `port.send` (nunca relê depois do próprio append). Append `Err` antes do envio é fail-closed e não chama `port.send`.
- [ ] `tests/app/t_turn_delivery_journal.nim` (dono exclusivo deste PRD, sem editar `t_turn_recovery.nim`): crash depois do enqueue e antes do envio → **exatamente 1** `port.send` após restart; crash depois do envio e antes de `tevDelivered` → **0** `port.send`, `rdsFailed` e 1 aviso; append falho antes do envio → **0** `port.send`; dois restarts não repetem envio nem aviso.

### US-006: Memória no máximo uma vez e transcript derivado
**Descrição:** Como mantenedor, quero memória sem duplicata e transcript explicitamente não recuperado.
**Critérios de aceite:**
- [ ] `app/orchestrator.nim` grava `tevMemoryPending` **antes** de `safeAppendMemory`, `tevMemoryWritten` depois e `tevMemorySkipped` quando `shouldSkipAutoMemoryCapture`; append `Err` é fail-closed (não chama `safeAppendMemory`); `tpsMemoryPending` na retomada vira `mwsLost` + `tpsCommitted`, sem reescrever.
- [ ] Após memória terminal, grava `tevTranscriptPending`, salva o transcript e grava `tevTranscriptSaved`; se faltar `twsSaved`, a retomada marca `twsLost` e **não** tenta reescrever (derivado; conteúdo já está na memória).
- [ ] `tests/app/t_memory_idempotency.nim`: crash após append/antes de `tevMemoryWritten` não duplica no port falso; crash antes de `tevMemoryPending` grava uma; port falho não grava memória; crash após `tevTranscriptPending` mantém transcript intocado e conta `twsLost`; `tests/app/t_append_memory_origin.nim` verde sem edição.

### US-007: Fiação no startup, replay e aviso
**Descrição:** Como mantenedor, quero executar o plano antes dos drainers, com tentativas limitadas.
**Critérios de aceite:**
- [ ] `src/donkey.nim` abre o diário após o lease e a reconciliação do ledger (`src/donkey.nim:1810`) e antes dos drainers; `replayModel` reenfileira o turno armazenado via `ensureSessionTask` com o mesmo `turnId`; `enqueueReply` usa `replyText` + `deliveryId`.
- [ ] Limites: `MaxModelReplays = 1`, `MaxNotices = 1`, `MaxRecoveryPasses = 2`; exceder incrementa `attempts` até abandonar em `tpsAbandoned` (terminal) com 1 aviso; `tevRecoveryNotified` é gravado **antes** do envio; o restart seguinte não repete.
- [ ] `DONKEY_TURN_JOURNAL=off` guarda só hashes e desabilita `replayModel` (turnos viram `abandoned` com aviso); log único `turn journal: N resumed, M reconciled, K duplicates, L abandoned, X lost`.
- [ ] `tests/app/t_turn_recovery_startup.nim`: matriz CP-1..CP-13, dois restarts, contagem de `port.send`/provider/memória por caso e nenhum aviso duplicado; `tests/state/t_daemon_lease.nim` e `tests/app/t_durability.nim` verdes sem edição.

### US-008: Documentar e fechar
**Descrição:** Como mantenedor, quero que a operação saiba o que o diário garante e o que não garante.
**Critérios de aceite:**
- [ ] `docs/topics/sessions.md` ganha “Turn journal e retomada” com ramos, política visível, schema/privacidade e tabela de janelas; documentar `twsLost`, `mwsLost` e reentrega.
- [ ] `docs/ops-drill.md` ganha drill: matar o daemon em cada janela e conferir `state/turn_journal.jsonl` + log; `rg -n "raise" src/donkey/domain/session src/donkey/app/turn_recovery.nim` vazio; `check_boundaries.sh` verde.
- [ ] Commit registra que o placar da V4 não muda: é durabilidade, não cobertura.

## 7. Requisitos funcionais

- **FR-1:** Todo turno de usuário tem `turnId` derivado do id do canal e um diário por evento.
- **FR-2:** `resumePlan` é puro e total sobre fases × entrega × memória × transcript.
- **FR-3:** No máximo um `port.send` da resposta final por `turnId`, inclusive após N restarts.
- **FR-4:** No máximo uma entrada automática de memória por `turnId`, escrita só pelo ator; transcript perdido é marcado `twsLost`, nunca reescrito.
- **FR-5:** Entrega `attempted` de processo morto é reconciliada como falha, nunca reenviada.
- **FR-6:** Aviso de recuperação é no máximo um por turno, escrito antes do envio.
- **FR-7:** Falha de append **antes** de um efeito é fail-closed: o efeito não acontece e o turno é abandonado com uma mensagem de falha.
- **FR-8:** O schema guarda inbound (texto/mídia), reply e hashes; nunca tools, requests ou anexos; `DONKEY_TURN_JOURNAL=off` reduz a hashes.
- **FR-9:** `MaxModelReplays=1`, `MaxNotices=1`, `MaxRecoveryPasses=2`; exceder é `tpsAbandoned`.
- **FR-10:** Só o adapter toca arquivo; “delivered/failed” é emitido por quem chama `port.send`.

## 8. Não-objetivos

- Exatamente-uma-vez para tools externas ou inbound do canal.
- Retomar heartbeat, onboarding ou controle com resposta pendente.
- Recuperar transcript perdido; ele é derivado e marcado `twsLost`.
- Substituir o delivery ledger (coexistem; o ledger segue dono da entrega).

## 9. Considerações técnicas

| CP | Janela | Estado no diário | Ação na retomada | Visível |
|---|---|---|---|---|
| CP-1 | inbound na fila do ator | accepted | replay model 1× | não |
| CP-2 | modelo em voo | accepted | replay model 1× | não |
| CP-3 | parcial de streaming emitida, sem reply | accepted + streamed | abandonar, sem replay | 1 aviso |
| CP-4 | replyReady antes do enqueue | replyReady/none | buffered: enqueue 1×; streamed: nada | resposta (memória lost) |
| CP-5 | enfileirado, antes do drainer | queued | envia 1× | resposta |
| CP-6 | `port.send` em voo/incerto | attempted | não reenvia; failed + aviso | 1 aviso |
| CP-7 | enviado, sem `tevDelivered` | attempted | não reenvia; failed + aviso | 1 aviso (falso positivo) |
| CP-8 | `tevDelivered` gravado pelo drainer | sent | nada na entrega | não |
| CP-9 | `tevMemoryPending` antes do append | pending | marca `mwsLost`, não duplica | perda contada |
| CP-10 | `tevMemoryWritten` | written | nada na memória | não |
| CP-11 | `tevTranscriptPending` antes do save | pending | `twsLost`, não reescreve | não |
| CP-12 | `tevCommitted` | committed | no-op + drop duplicata | não |
| CP-13 | 2º restart com replay já feito | accepted + `modelReplays=1` | abandona + 1 aviso | 1 aviso |

- Entrega, memória e transcript são ramos independentes: o plano combina ações, não uma
  fase linear. `rdsSent` só é gravado pelo drainer depois do `port.send`.
- Fail-closed antes do efeito; depois do efeito, at-most-once. Duplicar é pior do que
  perder; a perda aparece no relatório (`twsLost`, `mwsLost`) e no aviso.
- Schema/privacidade: texto inbound ≤ 16 KiB, até 10 URLs de mídia ≤ 2 KiB cada, reply ≤
  32 KiB, redigidos (`Bearer`, `sk-`, `key=`, `token=`) antes do append; diretório 0700,
  arquivo 0600. Sem conteúdo de anexo, tool args ou payload de provider.
- 4 a 8 eventos por turno; retenção 7 dias; replay O(ativos + janela).
- `turn_journal_pure.nim` não importa `os`/`chronos`/`json` de I/O: encoding/decoding são
  `func` sobre strings, como `lease_pure`.
- Escrita sempre **antes** do efeito correspondente; nenhuma recuperação roda antes de o
  diário estar aberto e o lease adquirido.

## 10. Métricas de sucesso

- 13/13 janelas com teste de restart; 0 duplicata de `port.send`, memória ou aviso.
- `resumePlan` exaustivo sobre todas as combinações de enums (teste tabelado).
- Relatório no log em todo startup, inclusive com 0 turnos; `mwsLost`/`twsLost` visíveis.
- Suíte total verde (baseline + testes novos), sem edição de teste existente; `check_boundaries.sh` exit 0.

## 11. Questões em aberto

- Retenção de 7 dias vs. 30 do ledger: alinhar em US-008 se a operação pedir.
- A cópia do aviso deve variar por canal? Começar única e revisar em US-007.
- Quem commitar primeiro em `src/donkey.nim` (provider, canais, interfaces, automação ou
  durabilidade) libera o arquivo; a ordem entre missões é operacional, não técnica.
[/PRD]
