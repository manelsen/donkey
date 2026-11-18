# Review — tasks/prd-durabilidade.md (V4 prioridade 7)

**Verdict: BLOCK.** O recorte, a tabela CP-1..CP-11, o TDD/gates e a compaction
são bons. Mas a fase linear não bate com o ciclo real do turno e há requisitos
contraditórios; US-004..US-007 não são implementáveis como estão. O worktree já
está sujo por outro dono (`quirks.nim` removido): a preparação manda parar.

## Correções obrigatórias

1. **Entrega é assíncrona; a fase linear não é.** `finalizeNormalTurn` só
   enfileira (`tool_loop_runtime.nim:616`); o drainer envia depois
   (`src/donkey.nim:1456`), e a memória é gravada **antes** de `tevDelivered`
   existir. Ninguém grava `tevDelivered`/`tpsDelivered`, e a ordem real
   (`attempted → memoryWritten → delivered`) viola “nunca anda para trás”.
   Separar entrega e memória em estados independentes (ou esperar ack) e dar dono
   ao evento (drainer/`outbound_runtime` com `TurnJournalPort`). O mesmo para o
   progresso: até dois puts por turno; só a resposta final leva `turnId-reply`.
2. **FR-7 contradiz FR-3/FR-4.** Append falho + “turno segue” deixa o efeito sem
   evento; no restart a fase anterior repete entrega/memória → duplicata. Ou
   fail-closed antes do efeito, ou assumir duplicata em falha de diário.
3. **Idempotência real, não detecção.** US-005 aceita “dois envios com o mesmo id
   deixam um registro no ledger”: `recordPending` é upsert e o envio ocorre antes
   de `markSent`, então o teste passa com **dois** envios. Exigir uma chamada a
   `port.send` (skip no envio quando o id já foi tentado), não só no planejador.
4. **`turnIdFor` não é calculável e não deduplica.** `msg.id` é `userId-seq`
   (`session_ingress.nim:146`), não o id do canal; `channelId` não chega ao ator
   (`encodeSessionPayload` só leva texto/media). Reentrega do mesmo `messageId`
   ganha seq novo → turnId novo → duplicata. Propagar `channelMessageId`/`chatId`
   ou calcular no ingress, e deduplicar pelo campo persistido.
5. **CP-8 inalcançável, fases mortas.** §9 não define ação para
   `tpsDeliveryFailed`/`tpsAbandoned`; nenhuma história grava `tevAbandoned` nem
   `tevDelivered` — CP-8 só existiria em fixture. Completar §9, US-001 e US-005.
6. **Janelas não cobertas.** (a) o inbound espera na fila e só é journalizado
   quando o ator começa: crash com fila cheia perde turnos — gravar no ingress ou
   declarar o limite; (b) `runToolLoop` publica parciais antes de `tevReplyReady`
   e o replay recria a bolha (presentationState vazio) → resposta visível
   duplicada, contra FR-3 — excluir com aviso ou criar CP próprio; (c) o
   transcript é salvo após `tevCommitted` e não é recuperado, embora §1 o liste
   como etapa.
7. **Privacidade e schema.** `replyText` é justificado só por CP-4, mas
   `traReplayModel` exige texto inbound e `mediaUrls`, que o PRD não manda
   guardar; §11 empurra a decisão para US-002 sem aceite. Fixar o schema do
   `TurnEntry` (remetente, chatId, channelMessageId, taskKind, texto inbound,
   `replyText|replyHash`, tentativas), teto por turno, 0600/0700 testado e
   redação/opt-out.
8. **Retomada sem limite.** Sem contador/máximo, cada restart re-replaya o modelo
   e reenvia aviso. Fixar máx. 1 replay e 1 entrega, com abandono visível.
9. **Ownership/conflito.** US-003 é dona de `tests/app/t_turn_recovery.nim` e
   US-005, paralela, acrescenta CP-5..CP-7 nele — viola “ninguém edita arquivo de
   outro”; arquivo próprio ou sequenciar. “Arquivos disjuntos” contra
   `prd-provider-transport` falha em `src/donkey.nim` (US-007 × US-009); e
   `src/donkey.nim`, `outbound_runtime.nim`, `domain/message.nim` e
   `orchestrator.nim` também são escritos por `prd-canais`, `prd-interfaces` e
   `prd-automacao` — um escritor por vez.
## Ordem recomendada

US-001 → US-002 → US-003 → US-004 → **nova US-004b** (drainer grava
`tevDeliveryAttempted`/`tevDelivered` via port) → US-005 → US-006 → US-007 →
US-008. US-006 corre em paralelo com US-005 só após a US-004b; US-003 deixa de
ser paralela à US-005. Resolver 1–5 no PRD antes da US-001.
