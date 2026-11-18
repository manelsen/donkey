# Achados de revisão adiados — #56 e #57

Consolidação das três revisões independentes (CodeRabbit CLI na onda 2, CLI nas
fundações e o bot na #57 com base `master`). **Nenhum item é `critical`.** Cada
linha traz o motivo do adiamento e o que a correção exige, para não virar dívida
anônima.

Estado: #56 mergeado em `master`; #57 pronta para revisão com os demais achados
corrigidos. Os itens abaixo são os **adiados de propósito**.

---

## A. Threading e ciclo de vida (arquitetural)

### A1. `globalOutbox` escrito por workers HTTP — major
`src/donkey.nim:1204` · revisão #56
O ator de `/v1/chat/completions` nasce no worker HTTP e escreve no mesmo
`AsyncQueue` que o loop do daemon drena, sem sincronização explícita. É o mesmo
padrão pré-existente de `/api/chat`.
**Por que adiado:** serializar o outbox ou mover a escrita para a thread dona
muda o modelo de concorrência de todo o ingress.
**Correção:** canal com lock explícito ou fila MPSC; teste de stress com 8
workers + daemon drenando.
**Risco atual:** corrida de baixa probabilidade sob carga; já existia antes.

### A2. Ação do dashboard roda na thread HTTP — major
`src/donkey/app/http_gateway.nim:384` · revisões #56/#57
`gwSessionActionFn` chama `ensureSessionTask` sobre `runtime.sm` (tabela, canais,
`msgSeq`) de um worker.
**Por que adiado:** exige despachar a ação para a thread dona da sessão (fila de
comando) e mudar o contrato do hook.
**Correção:** comando no inbox do daemon + resposta assíncrona; hoje o snapshot
de leitura já é publicado sob lock, a escrita não.

### A3. SSE servido por outro worker pode expirar — major
`src/donkey/app/http_gateway.nim:845` · revisão #57
O nap do SSE bombeia o dispatcher do worker atual, mas o ator pode estar em
outro worker; o pump não o alcança.
**Por que adiado:** depende de A2/A1 (um dono único para o dispatcher do turno).
**Correção:** o turno precisa rodar no worker que atende o stream, ou o stream
precisa observar por um canal sem depender do dispatcher alheio.

### A4. `poll` correlacionado por usuário, não por geração — major
`src/donkey/app/chat_bridge.nim:183` · revisões #56/#57
Depois do TTL, um terminal atrasado do turno A pode encerrar o turno B.
**Por que adiado:** exige token por registro atravessando `deliver` no daemon
(`src/donkey.nim`), o orquestrador e o outbox.
**Correção:** `register` devolve `turnToken`; `deliver`/`fail` só aceitam o token
da geração viva; o runtime carrega o token no `OutboundMessage`.

---

## B. Correlação e durabilidade do turno

### B1. Commit visível ≠ commit persistido — major
`src/donkey/adapters/state/turn_journal_store.nim:616` · revisão #56
Se o `fsync` do `tevCommitted` falha após a escrita, o frame está legível; a nova
tentativa vê o evento e retorna `Ok(false)` sem confirmar a persistência.
**Por que adiado:** exige distinguir "escrito" de "sincronizado" no frame (ex.:
campo de commit ou fsync por linha com confirmação).
**Correção:** `append` devolve `persisted: bool`; `commitIfTerminal` só reporta
sucesso com `persisted`.

### B2. `syncDir` falho não é repetido — major
`turn_journal_store.nim:240` · revisão #56
Primeiro append grava o arquivo, `syncDir` falha, o arquivo fica visível; o
próximo append vê `isNew == false` e não sincroniza o diretório.
**Por que adiado:** mesma família de B1; exige marcar "diretório pendente" no
estado do store.
**Correção:** flag persistida em memória + retry no próximo append.

### B3. Diretório de estado criado sem fsync do pai — major
`turn_journal_store.nim:174` · revisão #56
`createDir` adiciona entrada no diretório superior; só o diretório imediato é
sincronizado.
**Por que adiado:** impacto só em criação inicial + crash imediato.
**Correção:** `syncDir(parentDir(stateDir))` após criar.

### B4. Resposta streamada e ainda não enfileirada na recuperação — major
`src/donkey/domain/session/turn_journal_pure.nim:402` · revisão #56
`replyReady + rsStreamed + rdsNone` (crash antes do outbox) não tem plano de
reenvio definido; hoje é "nada", como CP-4.
**Por que adiado:** decisão de produto: reenviar texto que o usuário talvez já
tenha visto pela metade, ou avisar.
**Correção:** definir CP e plano (`sendQueuedReply` com nota, ou `markLost`).

### B5. Correlação por turno além do TTL — major (PRD)
`tasks/prd-interfaces.md:87` · revisão #56
Espelho em PRD de A4; o PRD reconhece a limitação mas não fixa identidade.
**Correção:** mesma de A4 + critério de aceite.

### B6. Desfecho da memória em crash antes de `tevMemoryPending` — major (PRD)
`tasks/prd-durabilidade.md:131` · revisão #56
Um critério exige gravar memória; outro diz o contrário.
**Correção:** escolher "sempre grava" ou "sempre descarta" no PRD e no FSM.

---

## C. Supervisor de subagentes (sete no mesmo arquivo)

### C1. `done` publicado antes do shutdown consolidar — major
`src/donkey/app/subagent_runtime.nim:682`
`awaitFanout` retoma enquanto um filho ainda cancela.
**Correção:** esperar o settlement em andamento, não só o supervisor.

### C2. Fail-fast espera o primeiro antes de sinalizar o resto — major
`subagent_runtime.nim:777`
B falha, o supervisor cancela A e espera seu settlement antes de cancelar C, que
pode concluir nesse intervalo.
**Correção:** sinalizar todos os irmãos primeiro, agregar depois.

### C3. Fan-outs concluídos nunca removidos — major
`subagent_runtime.nim:874`
Cada execução acumula plano, resultados e future em `mgr.fanouts`.
**Correção:** remoção após `awaitFanout` + limite/idade.

### C4. Prazo de espera depende do término do filho — major
`subagent_runtime.nim:647`
`withTimeout` (chronos 4.0.0) pede cancelamento e ainda espera o future.
**Correção:** deadline por relógio monotônico e abandono do future no vencimento.

### C5. `cancelSubagent` não aciona fail-fast — major
`subagent_runtime.nim:750`
Cancelar B deixa A seguir; a US-004 exige cancelar os irmãos.
**Correção:** distinguir cancelamento externo de supervisor e disparar o
fail-fast no externo.

### C6. Teto de tokens só no tick — major
`subagent_runtime.nim:233`
A e B concluem e o orçamento já estourou; C pode iniciar outra rodada.
**Correção:** checar o teto em cada `captureOutcome`.

### C7. Conclusão tardia aceita após o prazo agregado — major
`subagent_runtime.nim:794`
Um filho que conclui 50 ms depois de um deadline de 30 ms é aceito antes do
primeiro tick.
**Correção:** aplicar o deadline no instante da conclusão, não só no tick.

**Por que o bloco inteiro foi adiado:** são sete correções no mesmo arquivo, com
testes de tempo e concorrência; merece PR próprio e revisão dedicada.

---

## D. Automação

### D1. Recusa de id duplicado + inserção não atômicas — major
`tasks/prd-automacao.md:142` · revisão #56
`ctl add` faz `loadRecord` e `upsert` em duas aquisições de lock: dois `add`
concorrentes podem ambos passar.
**Correção:** operação `insertIfAbsent` no store, sob o mesmo lock (e `lockf`).

### D2. `upsert` pode sobrescrever a spec com snapshot antigo — major (PRD)
`tasks/prd-automacao.md:108`
Hoje o tick só grava watermark, mas o PRD prevê `upsert` de spec.
**Correção:** separar `upsertSpec` de `updateWatermark` no contrato.

### D3. Reabilitar schedule não avança o watermark — major (PRD)
`tasks/prd-automacao.md:170`
Daemon parado durante todo o período desabilitado: o primeiro tick pode fazer
catch-up.
**Correção:** `enable` grava `lastRunAtMs = agora` no ctl.

### D4. Firing normal × catch-up em `scSkip` — major (PRD)
`tasks/prd-automacao.md:107`
O texto ainda manda `catchUpInstant`, que devolve `none` para `skip`; a
implementação já usa `nextRunAfterMs`.
**Correção:** atualizar o critério do PRD para o comportamento implementado.

---

## E. Providers

### E1. Fireworks: modelo fora do serverless — major
`src/donkey/domain/providers/descriptors.nim:121`
`kimi-k2p6` teria saído do Serverless em 2026-09-25 (alegação do revisor, sem
fonte primária que eu possa citar).
**Por que adiado:** não troco default de provider com base em alegação não
verificada.
**Correção:** confirmar no catálogo oficial e trocar `DefaultModelFireworks`.

### E2. `reasoning_effort: "none"` aplicado a modelos que não aceitam — major
`profile_fireworks.nim:52`
Muse Spark Open rejeitaria o valor mesmo com reasoning off.
**Correção:** allowlist por modelo no perfil (dado verificável).

### E3. Marcador inline quando o perfil remove a imagem — major
`profile_fireworks.nim:53`
O orquestrador escreve "a imagem acompanha" e o perfil suprime `imageUrl`.
**Correção:** decidir inline por capacidade do provider escolhido, não só pelo
tipo de mídia.

### E4. Teste do Fireworks via `staticRead` — major (teste)
`tests/provider/t_fireworks.nim:36` e `t_alibaba.nim:30`
Procura textos no fonte do builder; não prova qual perfil foi escolhido.
**Correção:** injetar `HttpRuntimePort` no `CompatAdapter` e capturar a
requisição do bundle (o adapter hoje só fala `newHttpClient`).

---

## F. Canais / LINE

### F1. `/continue` usa outro serviço de códigos — major
`src/donkey/adapters/channel/line_runtime.nim:77`
`/mycode` no Telegram grava no resolver do Telegram; o LINE tem resolver próprio
com tabela de códigos vazia.
**Correção:** injetar um serviço de códigos compartilhado entre canais.

### F2. `/continue` faz POST síncrono no loop do daemon — major
`line_runtime.nim:83`
`send` pode esperar até 30 s; nesse intervalo Telegram e scheduler não rodam.
**Correção:** enfileirar a resposta com `replyTo` no outbox e não esperar.

### F3. Vaga da fila ocupada por evento já aceito — major
`src/donkey/adapters/channel/line.nim:94`
Sob saturação, o reenvio de A ocupa a vaga que B precisava.
**Correção:** admissão atômica por lote ou consulta ao cache de replay antes de
reservar espaço (o cache vive no runtime, não no adapter).

### F4. TOCTOU do anexo local no Telegram — major
`src/donkey/adapters/channel/telegram.nim:441`
Valida o caminho e depois lê; troca de symlink entre os dois passos.
**Correção:** `openat`/`O_NOFOLLOW` por componente e leitura pelo descritor
validado.

---

## G. Setup

### G1. Wizard perde o pool de credenciais — major
`src/donkey/app/setup_wizard.nim:45`
`OPENAI_API_KEYS=A,B` grava só `OPENAI_API_KEY=A`.
**Correção:** preservar o nome/forma do env de origem (plural) ao gerar o
`donkey.env`.

### G2. Perde as chaves específicas de OpenCode Go e Zen — major
`setup_wizard.nim:103`
Com `OPENCODE_GO_API_KEY` e `ZEN_API_KEY` e sem a compartilhada, grava uma linha
só.
**Correção:** gravar a chave específica de cada provider selecionado.

---

## H. Superfícies e contrato

### H1. Rotas do dashboard sem Bearer quando o token está vazio — major
`src/donkey/app/http_gateway.nim:654` · revisão #57
Comportamento histórico do gateway (loopback sem token). As rotas novas
`/api/sessions` e `/api/providers` herdam isso.
**Por que adiado:** mudar quebra o dashboard local de quem não configura token.
**Correção:** exigir token para `/api/*` mesmo em loopback, ou bind explícito
`127.0.0.1` + opção documentada.

### H2. Identidade por campo `user`, não por token — major (design)
`http_gateway.nim:598` · revisão #56
Um cliente com o token pode assumir qualquer `api:<nome>`.
**Por que adiado:** autenticação por usuário é não-objetivo explícito do PRD.
**Correção:** mapa token→usuário, se o produto quiser multi-tenant real.

### H3. Dedupe após retenção — major (PRD)
`tasks/prd-durabilidade.md:94`
Após a compactação, a reentrega do canal pode gerar segunda resposta.
**Correção:** retenção de chaves de inbound separada da de turnos.

### H4. Reagendar cleanup após timeout de settlement — major (PRD)
`tasks/prd-multiagente.md:121`
`settleChild` que vence em 2 s não remove o paddock e ninguém reagenda.
**Correção:** reenfileirar o cleanup no término tardio.

### H5. Cancelamento externo × supervisor — major (PRD)
`tasks/prd-multiagente.md:161`
Dois critérios se contradizem sobre `ssCancelled` disparar fail-fast.
**Correção:** decidir no PRD e alinhar C5.

---

## Ordem sugerida de ataque

1. **A4 + B1/B2** — correlação por geração e confirmação de persistência: é onde
   um crash ainda perde ou duplica resposta.
2. **C1–C7** — supervisor de subagentes, um PR só para o arquivo.
3. **F1/F2/F3** — LINE atrás de um serviço de códigos e de um worker de saída.
4. **A2/A3** — dono único da thread do turno (habilita SSE e dashboard).
5. **G1/G2**, **D1–D3**, **E1–E4**, **H*** — menor risco, podem ir em paralelo.

---

## Atualização — revisão da onda de dívida (PR #58)

Os achados abaixo nasceram da revisão da própria onda de dívida. Os majors
foram corrigidos; estes ficam como follow-up.

### A5. Envio de saída roda na thread do daemon — major (arquitetural)
`src/donkey.nim` (`drainGlobalOutbox`) · revisão #58
Todo `routeOutbound` chama `port.send` de forma síncrona no dreno do outbox, que
roda no thread do daemon. O `/continue` do LINE foi enfileirado (F2), mas o POST
apenas mudou de lugar: um endpoint lento bloqueia todos os canais e o scheduler
pelo timeout do transporte (30 s no LINE).

**Por que adiado:** exige um worker de saída (fila própria + thread) e uma
política de ordenação por usuário; é vizinho do A1.
**Correção:** fila de saída drenada por thread(s) de trabalho, com confirmação
por mensagem e o ledger atualizado lá.

### A6. Confinamento por descritor é Linux-only — major
`src/donkey/adapters/filesystem/paths.nim` · revisão #58
O `O_NOFOLLOW` cobre só o componente final; a prova de que o arquivo aberto
continua dentro da raiz vem de `/proc/self/fd/N`. Em macOS não há `/proc`, então
um diretório intermediário trocado por symlink passa.

**Correção:** no macOS, `fcntl(F_GETPATH)` no fd para revalidar a raiz; ou
`openat` component a component.

### C8. Conclusão tardia sobrescreve `ssTimedOut` — minor
`src/donkey/app/subagent_runtime.nim`
Um filho que conclui depois de o loop agregado encerrar pode registrar
`completed` sobre o `ssTimedOut` já marcado.

### C9. Remoção de filho com future pendente — minor
`subagent_runtime.nim`
A varredura de retenção pode remover um filho cujo future ainda não terminou.

### B7. Rename pendente sem retry quando não há nada a escrever — minor
`src/donkey/adapters/state/turn_journal_store.nim`
A confirmação do rename pendente só ocorre no próximo append com conteúdo.

### H6. Identidade por token — decisão de produto (inalterada)
Continua como não-objetivo do PRD; registrada aqui para não se perder.

### A7. `askInbox` não preserva a correlação — major
`src/donkey/app/session_ingress.nim:349-360` · revisão #58 (re-revisão)
Se uma reserva órfã expira enquanto `awaitingAsk` está ativo, um novo pedido do
mesmo usuário é entregue como **texto da pergunta** ao turno anterior; o turno
antigo responde com o token antigo e o novo pedido nunca roda (e o worker HTTP
espera até o deadline).

**Correção proposta (contida, precisa de teste):** quando `msg.bridgeToken != 0`
(um pedido da API) e a sessão está em `awaitingAsk`, cancelar a pergunta
(`__DONKEY_ASK_CANCELLED__`), limpar `awaitingAsk` e enfileirar o pedido como
task normal, em vez de entregá-lo como resposta. Para canais (token 0) nada
muda.

**Por que ficou fora desta rodada:** mexe na semântica do `ask` e não há
harness de teste para ask+token; um patch sem teste nesse caminho é pior que a
dívida documentada.
