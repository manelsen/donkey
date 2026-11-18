# Review — tasks/prd-automacao.md (V4 prioridade 6)

**Verdict: PASS WITH FIXES.** Recorte correto (cron persistido + retenção, não um segundo heartbeat), histórias pequenas, TDD/gates copiados do `prd-provider-transport.md`. Quatro semânticas precisam ser fechadas **no PRD** antes da US-003: at-most-once, borda de `nextRun`, tick vs cron do heartbeat, e corrida `ctl`×daemon.

## Correções obrigatórias

1. **Dedupe (US-004).** "Pular se já há `sent`" é insuficiente: se `markRun(sent)` devolver `Err`, resta `pending` e o próximo tick reenfileira → duplicata. Pular se existir **qualquer** marcador (`pending`|`sent`) para `(scheduleId, instant)`; falha ao gravar `sent` não reabre o firing.
2. **Marcador durável.** `pending` precisa de fsync (arquivo + dir) **antes** do `enqueue`; hoje só diz "gravar". Append de `pending` com `Err` → **não** enfileirar, devolver `Err` (fail-closed). É o oposto de `runtime_store.recordPending` (`durable=false`), que aceita duplicata.
3. **Teste de crash real (US-004).** Só há store/clock falsos. Exigir um caso com store real em dir temporário: grava `pending`, descarta a instância, reinstancia, `reconcileInterruptedRuns` → `failed`, nada reenfileirado.
4. **US-006 não pode montar no registry cron.** `src/donkey.nim:1897-1908`: com `DONKEY_HEARTBEAT_CRON` o registry roda no cron (pode ser diário) e `DONKEY_SCHEDULES_TICK_SEC` é ignorado. Usar `startPeriodicTask`/registry próprio e declarar no aceite.
5. **Borda/horizonte (US-002).** Falta: (a) `nextRunAfterMs` inclusivo ou exclusivo no minuto de `nowMs`; (b) cron que nunca casa (`0 0 30 2 *` parseia) → `Option[int64]`, não sentinela; (c) `scOnce` pega a ocorrência **mais recente** por busca para trás, não 527k minutos/tick; (d) `nowMs < lastRunMs` (relógio para trás) → janela vazia, sem crash; (e) teste provando que `dueInstants` devolve epoch **real** (offset removido), não o UTC deslocado.
6. **Catch-up com `scOnce`.** "Lookback de uma ocorrência" faz um `0 9 * * *` criado às 15h disparar no 1º tick. Decidir e testar (ex.: 1ª observação não dispara, `lastRunMs` inicial = `nowMs`). `DONKEY_SCHEDULE_CATCHUP` é default **na criação** (campo do spec vence), parseado em `src/donkey.nim` e injetado — nunca lido dentro do adapter.
7. **Lost update em `schedules.json` (US-003).** Atomic rename evita arquivo truncado, não corrida: dois `ctl` fazem load→modify→write e um schedule some. Exigir flock/lockfile, tmp único (`pid-seq`) e fsync do dir. Acrescentar `version` + regra do ledger (`hasForwardIncompatibleEvents`): compactação não descarta evento de versão futura, senão rollback duplica disparos.
8. **Ownership/paralelismo (§4.2, §5).** `src/donkey.nim` é da US-006 mas US-008 pede ajuda lá → mover para US-007. §5 erra ao dizer "zero sobreposição" com `prd-provider-transport.md`: a US-009 do outro PRD também edita `src/donkey.nim` — serializar. Faltam donos: `orchestrator.nim`, `agent_message.nim`, `session_ingress.nim` (US-005), `schedule_store.nim`. E "US-003..008 em paralelo entre si" é falso: US-004←003, US-006←004+005, US-008←US-007 (`schedule_view.nim`).
9. **Verificabilidade (US-007).** `failures` não existe no store e a compactação apaga histórico: definir "estado da última execução" **ou** count sobre runs retidos (testado). Definir tipo/validação de `channel` e o que `ctl add` faz com id duplicado (erro, não upsert silencioso).
10. **Não-objetivos faltando.** (a) `sent` = enfileirado no inbox da sessão, não entregue no canal; (b) at-most-once pressupõe **um** processo (daemon lease); (c) sem teto de schedules/usuário — decidir 50 na US-003; (d) `enabled=false` não ticka; ao reabilitar, catch-up vem do `lastRun` inalterado (teste).

## Sem problemas

Cron reusa `core/cron` (DOM/DOW OR, passo, 5 campos); offset fixo bem delimitado (recusa IANA, `−840..840`, sem `times.local`) — documentar só que mudar o offset não retro-dispara. Store espelha `runtime_store` (corrupt→`.corrupt-<epoch>`, newline-framed, retenção com clock injetado, `func` puras, `Result`, sem `raise`). Baseline 242 e gates idênticos ao PRD de referência.

**Ordem:** 001 → 002 → 003 → 004 → 005 → 007 → 006 → 008; 005 em paralelo a 002/003 e 007 a 004; suíte e commits só na sessão principal.
