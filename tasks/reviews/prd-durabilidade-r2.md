# Re-review — tasks/prd-durabilidade.md (r2)

**Verdict: PASS WITH FIXES.** Os 9 achados anteriores foram endereçados; restam 5
correções concretas, nenhuma exige mudar o recorte.

| # | Achado | Situação |
|---|---|---|
| 1 | Ciclo, dono do `delivered` | **Fechado** no ramo bufferizado (§1, ramos independentes, US-004b, CP-8). Ver B. |
| 2 | FR-7 vs duplicata | **Fechado**: fail-closed antes, at-most-once depois, teste por efeito. Ver D. |
| 3 | US-005 só contava ledger | **Fechado**: 1 / 0 pós-envio / 0 append falho / 2 restarts; skip no drainer por `ownerEpochMs`. |
| 4 | `turnId` instável | **Fechado**: id do canal, fallback, dedup por `loadByInbound`. Telegram/Matrix/Signal/CLI/WeCom usam `channelId` por mensagem. |
| 5 | Fila, parciais, transcript | **Fechado**: journal antes de `addLastNoWait` (CP-1), `tevStreamStarted` + CP-3 sem replay, `twsLost`/CP-11. Ver B, C. |
| 6 | Privacidade/schema | **Fechado**: `TurnEntry` fechado, 16/32 KiB + 10 URLs, redação testada (US-002), 0600/0700, modo `off`. |
| 7 | Retomada sem limite | **Fechado**: `MaxModelReplays/Notices/Passes`, `tpsAbandoned`, aviso antes do envio, CP-13. Ver E. |
| 8 | Ownership | **Fechado**: §5.4 + um escritor por vez; `quirks.nim` alheio não bloqueia; US-005 com arquivo próprio. |
| 9 | Ordem | **Fechado**: `001→…→004b→005→006→007→008`; US-003 não paralela a US-005. |

## Correções restantes

**A. `tevCommitted` sem escritor no caminho feliz (crítico).** Só US-006 o grava na
retomada. Sem ele CP-12 nunca dispara → reentrega do mesmo `messageId` responde de
novo, e a compaction “mantém ativos” (linha 98) cresce sem limite. Definir emissão
(entrega terminal + memória/transcript terminais) e testar que o turno sai de ativo.

**B. Final streamed sem `queued`/`attempted` (crítico).** US-004 diz que streamed não
usa `queued` e US-004b só journaliza `sendImmediateOutbound`; o final streamed vai por
`outbox.put` → drainer → `editStreamOutbound` (`outbound_runtime.nim:271-283`), e
`createStreamOutbound`/`createReplacementOutbound` chamam `port.send` sem o port. Logo:
(i) crash entre `outbox.put` e o drainer perde a resposta sem aviso (CP-5 não vale;
CP-4 streamed = “nada”); (ii) CP-8/`rdsSent` fica inalcançável em Telegram/Discord.
Fixar: journal em todo caminho que chame `port.send` e evento de “final enfileirado”
para streamed, reenviando como mensagem simples se não houver `attempted`.

**C. CP-3 × CP-4-streamed indistinguíveis.** `TurnEntry` não registra “parcial já
emitida” (`rsStreamed` + `rdsNone` serve aos dois) e `TurnEvent` é citado sem variantes
em US-001 — `resumePlan` total e o decoder de US-002 não são escrevíveis TDD-first.

**D. FR-7 gera 2ª mensagem.** “Abandonado com uma mensagem de falha” vale também para
append de memória/transcript, quando a resposta já foi enfileirada → mensagem extra e
possível 2º aviso, contra FR-6. Restringir a falha antes do `enqueueReply`.

**E. `attempts` off-by-one.** US-004 grava `attempts=1` no ingress, mas §9/US-007 usam
`attempts` como passes com `MaxRecoveryPasses=2` → turno saudável abandonado após 1
restart. Começar em 0 e incrementar só na retomada.

Nit (não bloqueia): `finalizeNormalTurn` está em `tool_loop_runtime.nim:583`, não `:616`.