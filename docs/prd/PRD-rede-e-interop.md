[PRD]
# PRD Rede e interoperabilidade: a conexão vai aonde foi conferida, e o A2A fala com quem existe

> **Situação em 27/11/2026:** rascunho. As decisões marcadas **[proposta]**
> são padrões sugeridos que o mantenedor confirma antes da execução; o
> resto é execução.
>
> **Depende de:** nada novo; o A2A (E13.4, #273 e #274) e o canal como
> processo (E12.3, #270 a #272) estão no master.
> **Vem antes de:** [PRD Computador por pessoa](PRD-computador-por-pessoa.md)
> (o portão de rede dela parte da conexão conferida desta).

> **Executor:** agente autônomo. Leia este documento inteiro antes de
> começar. Execute as etapas **na ordem**. Cada etapa termina com os quality
> gates verdes e um commit próprio. Se a sessão for interrompida, retome pela
> primeira etapa sem commit, conferindo `git log --oneline` contra os
> títulos de commit. **Não improvise decisões:** o que não estiver decidido
> aqui volta ao mantenedor como pergunta.

## 1. Visão

Duas promessas que hoje o Donkey faz pela metade:

1. **Um endereço conferido é o endereço conectado.** Quando o Donkey decide
   que um nome aponta para fora da rede interna e só então se conecta, a
   conexão tem de ir ao endereço que ele conferiu, não a outro que o DNS
   devolva um instante depois (*DNS rebinding*).
2. **O que fala um protocolo fala com quem o implementa.** O A2A do Donkey
   foi escrito a partir da especificação, sem contato com nenhuma outra
   implementação. Ele precisa ser provado contra o SDK oficial, nos dois
   sentidos, com as conversas reais gravadas como fixtures.

## 2. Contexto (conferido em 27/11/2026 no master `81f0c854`)

- **A janela de rebinding está documentada no próprio código.**
  `app/tools/web_tools.nim`: "DNS is validated here, but std/httpclient
  resolves again when dialing. Full connection pinning against DNS
  rebinding requires the filtering egress proxy (DONKEY_WEB_PROXY) or a
  firewall." O comentário é anterior ao `deadline_transport`, que também
  resolve de novo ao conectar (`resolveTAddress` no worker).
  `adapters/tools/browser.nim` diz o mesmo do navegador.
- **A checagem existe:** `adapters/network/dns_resolver.safeResolve` resolve
  e só aceita quando todos os endereços são públicos (`core/network.nim`,
  guarda de SSRF); o `StdHttpAdapter` a expõe como `resolveHost`.
- **O Supernova fechou a mesma janela em 27/11** (`web_fetch conecta no
  endereço conferido`, M7): resolve uma vez, confere todos os endereços,
  conecta ao IP conferido com `Host`, SNI e certificado pelo nome.
- **A2A:** servidor v1.0 (`domain/a2a/a2a_pure`, `app/a2a_server`) e cliente
  (`domain/a2a/a2a_client_pure`, `delegate_to_agent`), testados só contra
  JSON escrito a partir da especificação. A chamada fora do laço tem 30 s
  (`OffLoopHttpTimeoutSec`): um agente que segura o `SendMessage` mais que
  isso estoura.
- **Confirmar um pareamento só por canal:** `/editor <código>`; não há
  `ctl` que confirme, o que impede um teste de ponta a ponta sem canal.
- **IRC como processo:** testado só com servidor falso sem TLS; o filho
  exige TLS (`IrcSettings.tls`, sempre verdadeiro no daemon).
- **Fixtures gravadas contra a API real** são o método do Supernova
  (`dev/gemini/gravar.py`, PRD-A): a gravação corrigiu duas suposições.

## 3. Decisões

| # | Decisão |
|---|---|
| R1 | **[proposta]** A resolução é feita **uma vez** por requisição, no transporte (`deadline_transport`); todos os endereços são conferidos; a conexão vai ao primeiro endereço aceito, com `Host`, SNI e verificação de certificado pelo **nome**. |
| R2 | **[proposta]** Vale para **toda** saída que passa pelo `StdHttpAdapter` com a guarda de rede ligada (ferramentas web, MCP por HTTP, A2A, canais), não só para o `web_fetch`. Os destinos internos que a configuração declara (um provider local, um Ollama) continuam aceitos pela lista que já existe. |
| R3 | **[proposta]** O navegador (Lightpanda, no processo do daemon) **fica fora desta PRD**: a resposta para ele é tirá-lo do daemon ([PRD Computador](PRD-computador-por-pessoa.md), E25). Até lá, a janela continua documentada. |
| R4 | **[proposta]** As fixtures do A2A são gravadas contra o **SDK oficial em Python**, nas versões 1.0 e 0.3, rodando localmente em ambiente isolado; nada é publicado; a gravação é um script do repositório (`dev/a2a/`), reexecutável. |
| R5 | **[proposta]** O prazo de uma chamada A2A passa a ser **por agente** (`timeout_sec` em `[[a2a.agents]]`), padrão **120 s**, teto 600 s. |
| R6 | **[proposta]** `donkey ctl editor confirm <código> <uuid>` confirma um pareamento pendente pelo operador (útil a testes e a quem não tem canal à mão); registrado no log de auditoria. |
| R7 | **[proposta]** O IRC é provado contra o **Ergo** local com certificado próprio; o Donkey ganha `IRC_TLS_CA` (um arquivo de CA extra), usado só quando definido. |

## 4. O que muda para quem usa

- Nada visível no dia a dia: um site que tente trocar de endereço entre a
  checagem e a conexão passa a ser recusado com uma mensagem clara.
- Quem delega a um agente lento deixa de ver "não respondeu" aos 30 s.
- O operador confirma um pareamento sem precisar de um canal.

## 5. Fora de escopo

- O navegador (R3).
- Streaming, push e arquivos no A2A.
- Um proxy de egress próprio do Donkey.

## 6. Quality gates

Os de sempre (`CLAUDE.md`, "Processo de trabalho"): TDD com o vermelho
visto; suíte completa, build e `scripts/check_boundaries.sh` verdes antes
do primeiro push; nas correções de revisão, os testes tocados e o build.
Mais:

- **Nenhum teste depende de DNS de verdade:** o resolvedor é injetado; um
  servidor local faz o papel do destino.
- **As fixtures são arquivos do repositório** (`tests/fixtures/a2a/`), com a
  versão do SDK e a data da gravação no nome ou num cabeçalho; nenhum teste
  chama a rede.

## 7. Invariantes (cada uma com teste)

- **R-I1 – Conferido é conectado.** Com um resolvedor que devolve um
  endereço público na checagem e um interno na conexão, nenhuma conexão
  chega ao interno.
- **R-I2 – O nome continua sendo o nome.** Conectar ao IP não muda o `Host`,
  o SNI nem a verificação de certificado: um certificado válido para o nome
  passa; um válido só para o IP não.
- **R-I3 – O que foi gravado é o que se testa.** Cada fixture do A2A vem de
  uma gravação real; nenhuma é editada à mão (o script regrava).
- **R-I4 – Um pareamento confirmado pelo operador fica no log.** Quem
  confirmou, quando, para quem.

## 8. Épicos e etapas

### E14 — A conexão vai ao endereço conferido

#### E14.0: Linha de base

Listar todo caminho de saída HTTP do daemon e dizer, para cada um, onde o
nome é resolvido e quantas vezes (ferramentas web, MCP HTTP, A2A, canais,
providers, `offloop_jobs`).

**Aceite:**
- [ ] `docs/relatorios/PRD-rede-base.md` com a tabela.
- [ ] Commit: `docs: PRD rede, linha de base`.

#### E14.1: Resolver e conectar num passo só

No `deadline_transport`, a resolução injetável devolve os endereços; todos
são conferidos (R1); a conexão vai ao endereço aceito, com `Host` e SNI
pelo nome.

**Aceite:**
- [ ] R-I1 e R-I2 testados com resolvedor falso e servidor TLS local.
- [ ] Um destino declarado interno (provider local) continua alcançável.
- [ ] Commit: `fix(http): a conexão vai ao endereço conferido`.

#### E14.2: Os chamadores sem a segunda resolução

`web_fetch` e os redirecionamentos manuais deixam de resolver por conta
própria; o comentário que documenta a janela sai.

**Aceite:**
- [ ] Teste de rebinding no `web_fetch` com redirecionamento.
- [ ] Commit: `fix(web): web_fetch usa a conexão conferida`.

#### E14.3: Documentação

`docs/topics/` (segurança e ferramentas web): o que é conferido, o que
continua fora (navegador, R3).

**Aceite:**
- [ ] Commit: `docs: a conexão conferida`.

### E15 — A2A contra implementações reais

#### E15.0: O gravador

`dev/a2a/`: um ambiente isolado com o SDK oficial (1.0 e 0.3), um agente de
exemplo que responde na hora, um que demora (tarefa em andamento), um que
falha; um script que conversa com eles e grava pedidos e respostas.

**Aceite:**
- [ ] `dev/a2a/README.md` diz como regravar.
- [ ] Commit: `dev(a2a): gravador de conversas com o SDK oficial`.

#### E15.1: O cliente contra as gravações

`t_a2a_client_pure` e `t_a2a_delegate` passam a ler as fixtures gravadas:
tarefa pronta, em andamento até pronta, falha, mensagem direta, e a recusa
de um servidor 0.3 ao `SendMessage`.

**Aceite:**
- [ ] R-I3: cada caso aponta para um arquivo gravado.
- [ ] O que divergir da especificação lida vira correção com teste.
- [ ] Commit: `test(a2a): o cliente contra conversas gravadas`.

#### E15.2: O servidor contra o cliente oficial

O cliente oficial chama o servidor do Donkey (em loopback, provider falso);
os pedidos que ele manda são gravados e viram fixtures do servidor.

**Aceite:**
- [ ] O card do Donkey é aceito pelo cliente oficial.
- [ ] `SendMessage` e `GetTask` do cliente oficial funcionam contra o Donkey.
- [ ] Commit: `test(a2a): o servidor contra o cliente oficial`.

#### E15.3: O prazo por agente

`timeout_sec` em `[[a2a.agents]]` (R5), levado até o `HttpPostJob`.

**Aceite:**
- [ ] Padrão 120 s; acima de 600 s é recusado no carregamento.
- [ ] Commit: `feat(a2a): prazo por agente`.

#### E15.4: Confirmar pelo operador

`donkey ctl editor confirm <código> <uuid>` (R6), com log de auditoria.

**Aceite:**
- [ ] R-I4 testado.
- [ ] Commit: `feat(ctl): o operador confirma um pareamento`.

#### E15.5: De ponta a ponta

Dois daemons em loopback, isolados (`HOME` e `DONKEY_HOME` temporários,
provider falso): um pareia o outro pelo `ctl` e delega uma tarefa.

**Aceite:**
- [ ] O teste roda na suíte sem rede externa.
- [ ] Commit: `test(a2a): dois Donkeys conversam`.

### E16 — IRC contra um servidor real

#### E16.1: A CA extra

`IRC_TLS_CA` (R7): um arquivo de CA usado além das do sistema, só no IRC.

**Aceite:**
- [ ] Sem a variável, nada muda.
- [ ] Commit: `feat(irc): uma CA extra para o servidor`.

#### E16.2: O filho contra o Ergo

Um teste de integração, opcional na suíte (como os de navegador do
Supernova), sobe o Ergo com certificado próprio e roda o IRC como processo:
registro, SASL, uma mensagem e a resposta, o filho morto e reiniciado.

**Aceite:**
- [ ] `scripts/` tem o roteiro; o teste pula, com aviso, sem o Ergo.
- [ ] Commit: `test(irc): o processo filho contra um servidor real`.

## 9. Riscos

- **Certificados por IP.** Conectar ao IP e verificar pelo nome exige que o
  transporte separe os dois; um erro aqui quebra toda saída HTTPS. A etapa
  E14.1 tem o teste de certificado (R-I2) antes de qualquer chamador mudar.
- **SDK oficial mudando.** As fixtures registram a versão; regravar é um
  comando.
- **Ergo fora da máquina do CI.** O teste é opcional (E16.2) e não bloqueia
  a suíte.
