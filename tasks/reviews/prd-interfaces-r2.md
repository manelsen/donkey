# Re-review — `tasks/prd-interfaces.md` (r2)

**Verdict: PASS WITH FIXES.** Os oito itens anteriores foram incorporados; restam quatro lacunas
concretas, todas na US-002 (uma de correlação, duas de aceite/teste e uma de tipo).

## Verificado
1. ✓ `isApiChatReply` = `$msg.userId` com prefixo `api:`; sem `replyTo`/`sessionReplyTo`; entrega sem
   entrada pendente descartada (ressalva no fix 1).
2. ✓ Taxonomia, `toolCall` ≠ conteúdo, teste de turno com tool (ressalvas nos fixes 2 e 3).
3. ✓ `authorize` injetado, antes de `dispatch`, 403 negativo e teste (ressalva no fix 4).
4. ✓ `UsageTotals`/`addUsage*` somando rodadas streamadas; 413 >1 MiB em `runAgentChat`; `now`/`nap`
   no `ChatBridge`, sem `sleep` real.
5. ✓ `parseSessionTaskPath` cru, sem `apiUserId`; casa com `sm.entries` chaveado por `string(UserId)`.
6. ✓ `http_gateway.nim`/`src/donkey.nim` serializados US-002 → US-003 → US-004.
7. ✓ `t_orchestrator_control` removido (só o binário velho); 4 pendentes / 6 long-lived / 2 reservados.
8. ✓ Donos e não-objetivos; US-001 mexe em `domain/message.nim` só aditivamente.

## Correções restantes
1. **Resposta tardia pode fechar o turno seguinte.** `abandon`/504 remove a chave e um novo `register`
   do mesmo usuário é aceito enquanto o turno A ainda roda; como `deliver` casa só `$userId`, o final de
   A fecha o turno B. "Tardias descartadas" só vale enquanto não há entrada. Fix: reservar a chave até o
   terminal do órfão (429 para o próximo) ou identificar o turno na entrega (ex.: `streamId`, já
   `$userId & "-" & seq`); teste: A abandonado → B registrado → final de A não vira conteúdo de B.
2. **US-002 ignora streaming interno.** `streamToOutbox` emite `isPartial=true` e um final mesmo sem
   `stream: true`; o PRD só define coalescência na US-003. Fix: em `runAgentChat`, conteúdo = só o
   evento terminal (parciais nunca concatenados); teste parcial+final devolve **um** texto igual ao final.
3. **Teste do done-text não pega o vazamento que motivou o item.** `buildToolLoopDoneText` é
   `"✅ N tool call(s)"` com `isPartial=false`; o aceite só proíbe `🔧`. Fix: afirmar `content` == texto
   final e sem `✅`/`tool call(s)`/`toolCall`.
4. **`AuthVerdict` não tem dono.** `avRevoked`/`avNotAllowed` não existem em `src/` (só
   `isRevoked: proc(UserId): bool` no ingress). Fix: declarar o enum e o arquivo (p.ex. `identity_pure`)
   e o corpo do 403, para o teste da US-002 vir primeiro.

**Menor:** nomear `MaxApiRequestBytes` uma vez (o gateway já tem `GatewayMaxBodyBytes`, 1 MiB) para os
dois 413 não divergirem; dizer que o teto de 6 workers é checado como total (4 pendentes + 4 SSE = 8).

**Nota:** worktree sujo com a US-001 em andamento e arquivos alheios à missão; o gate do §4.1 vale na
execução (não é defeito do PRD).
