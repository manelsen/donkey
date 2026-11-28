[PRD]
# PRD Aprovação acessível: a pessoa responde do jeito que conseguir, e só ela decide

> **Situação em 27/11/2026:** rascunho. As decisões marcadas **[proposta]**
> são padrões sugeridos que o mantenedor confirma; a decisão **A5** está em
> aberto e volta a ele antes da etapa E20.6.
>
> **Depende de:** aprovações (`app/approval_runtime`, E5.2), escrita no
> GitHub (E11) e A2A (E13.4), todos no master. A etapa E20.3 (a voz decide)
> depende da [PRD Mídia acessível](PRD-midia-acessivel.md), E18.1.
> **Vem antes de:** [PRD Computador por pessoa](PRD-computador-por-pessoa.md)
> (o portão de envio pede por este caminho).

> **Executor:** agente autônomo. Leia este documento inteiro antes de
> começar. Execute as etapas **na ordem**. Cada etapa termina com os quality
> gates verdes e um commit próprio. Se a sessão for interrompida, retome pela
> primeira etapa sem commit, conferindo `git log --oneline` contra os
> títulos de commit. **Não improvise decisões.**

## 1. Visão

Uma aprovação só protege se a pessoa consegue responder a ela. Hoje o Donkey
pergunta com botões e espera `/approve <id>`: quem usa leitor de tela ouve
primeiro um emoji, quem está num canal sem botões precisa copiar um código,
quem só consegue falar não tem como responder.

Três promessas, garantidas pelo **código**, não pelo modelo:

1. **A pessoa responde por botão, texto ou voz.** "Sim", "pode", "não",
   "sim 2", uma nota de voz dizendo "sim": o código reconhece e decide.
2. **Só a pessoa decide.** Nem outra pessoa no mesmo grupo, nem o modelo,
   nem uma mensagem que pareça uma resposta.
3. **O pedido se entende sem ver a tela.** A primeira frase é do código,
   curta, com o essencial; a explicação da agente vem depois.

E um princípio que atravessa tudo (do Supernova, PRD-K, nascido do
feedback de uma profissional de acessibilidade): **a pessoa pode não
enxergar a tela nem usar as mãos.** O Donkey serve equipes pequenas; nelas
também há quem use leitor de tela, ditado ou só o celular.

## 2. Contexto (conferido em 27/11/2026 no master `81f0c854`)

- **O pedido** (`approval_runtime.requestAndWait`): cria o pedido no store
  (`ApprovalStorePort`), põe no outbox uma mensagem
  `"⚠️ *Aprovação necessária: <ferramenta>*\n\n<resumo>"` com botões, e
  **o turno espera** a decisão por `DONKEY_APPROVAL_TIMEOUT_SEC` (padrão
  **300 s**); sem resposta, nega.
- **As respostas reconhecidas** (`tryHandleApprovalInput`): `/approve <id>`,
  `/deny <id>`, `/poll`, os dados dos botões (`approval:<id>:allow|deny`) e
  o "sempre". **Um "sim" solto não decide nada:** vai ao modelo.
- **Permanentes** (`StandingApprovalPort`, E5.2): por pessoa e chave (hoje,
  a amostragem de um servidor MCP), sem prazo; revogadas por
  `donkey ctl approval standing revoke`. Não há comando no chat.
- **Canais sem botões** (IRC, SMS, ntfy, SimpleX, BlueBubbles, Email): o
  texto do pedido diz `/approve <id>`.
- **Voz:** uma nota de voz chega como anexo; só vira texto se o modelo
  chamar `transcribe_audio` (ver PRD Mídia).
- **Grupo:** o pedido vai ao chat do turno; **a conferir na linha de base**
  se, num grupo, outra pessoa consegue decidir (o store recebe o `userId`
  de quem respondeu e o compara com o dono do pedido).
- **No Supernova (PRD-K, 26/11):** botão, texto e voz reconhecidos pelo
  código; numeração com vários pendentes; pedido de grupo vai ao privado;
  lembrete às 3 h; expira em 24 h; permissão por site com prazo escolhido
  pela pessoa (1 h, 24 h, sempre); primeira frase do código com no máximo
  140 caracteres, sem emoji nem símbolo no início.

## 3. Decisões

### 3.1 Responder

| # | Decisão |
|---|---|
| A1 | **[proposta]** Com **um** pedido pendente da pessoa, uma mensagem que seja só um sim (`sim`, `s`, `pode`, `aprovo`, `ok`, `isso`, `yes`, `y`) ou só um não (`não`, `nao`, `n`, `recuso`, `cancela`, `no`) decide o pedido e **não vai ao modelo**. Pontuação e caixa são ignoradas; qualquer outra palavra faz a mensagem seguir para a agente, e o pedido continua pendente. |
| A2 | **[proposta]** Com **vários**, eles são numerados no texto de cada pedido; a resposta precisa do número (`sim 2`); um "sim" sozinho faz o código listar os pendentes. |
| A3 | **[proposta]** Uma **nota de voz** cuja transcrição seja só um sim ou um não decide como texto (depende da transcrição antes do turno, PRD Mídia E18.1). |
| A4 | **[proposta]** O texto do pedido começa por **uma frase do código**, no máximo 140 caracteres, sem emoji nem símbolo no início, com o essencial: o que, onde, para quem ("Publicar um comentário na issue 12 de acme/site."). Depois, numa linha própria, como responder ("Responda sim ou não."); depois, o resumo inteiro. |

### 3.2 Esperar

| # | Decisão |
|---|---|
| A5 | **Em aberto.** Hoje o turno espera até 300 s e nega. Duas saídas: **(a)** manter a espera no turno, com prazo maior (por exemplo 15 min) e um lembrete no meio; simples, mas o turno fica parado e a sessão também. **(b)** como o Supernova: sem resposta no prazo curto, o turno segue dizendo que pediu confirmação; o pedido fica pendente até **24 h**, com um lembrete às **3 h**; um "sim" depois vira uma **autorização** e chega à agente como mensagem ("[Aprovação #N] aprovada"), que refaz o passo. **Recomendação: (b)**, porque uma pessoa que demora a responder (cega, em reunião, dormindo) não deve perder o pedido nem travar a conversa. |
| A6 | **[proposta]** Um pedido nascido num **grupo** vai para o **privado** da pessoa; no grupo, a agente só diz que pediu confirmação no privado. Num canal sem privado, fica no chat do turno. |

### 3.3 Permitir por mais tempo

| # | Decisão |
|---|---|
| A7 | **[proposta]** Permissões permanentes ganham **prazo escolhido pela pessoa**: 1 hora (`sim 1 hora`), 24 horas (`sim 24 horas`) ou sempre (`sim sempre`); o botão "sempre" passa a oferecer os três onde couber. |
| A8 | **[proposta]** Admitem permissão por prazo: a amostragem de um MCP (como hoje), uma ferramenta de alto risco por pessoa (`bash`, `fs_write`…), um repositório e ação do GitHub, um agente A2A. **Nunca admitem:** o que o operador marcou como "sempre pergunta" (a escrita do GitHub em `ask` continua perguntando a cada vez, E11.3). |
| A9 | **[proposta]** `/permissoes` no chat lista e revoga as permissões da própria pessoa; a agente pode **revogar** a pedido da pessoa, **nunca conceder**. |

## 4. O que a pessoa vive

- Num canal sem botões, a agente pede: "Publicar um comentário na issue 12
  de acme/site. Responda sim ou não." A pessoa responde "pode"; o comentário
  sai; a agente confirma.
- Dois pedidos pendentes: "sim" lista os dois, numerados; "sim 2" aprova o
  segundo.
- Num grupo, a agente diz "pedi sua confirmação no privado"; o colega que
  responde "sim" no grupo não decide nada.
- Com A5 (b): a pessoa responde três horas depois; a agente recebe a
  aprovação e termina o que pediu.
- "Pode usar o bash por uma hora": `sim 1 hora`; uma hora depois, volta a
  perguntar. `/permissoes` mostra e revoga.

## 5. Fora de escopo

- Aprovação por terceiros (um gestor aprova pela equipe).
- Mudar quais ferramentas pedem aprovação (`DONKEY_APPROVAL_TOOLS`).
- O portão de rede do computador (PRD Computador).

## 6. Quality gates

Os de sempre (`CLAUDE.md`). Mais:

- **Leitor de tela:** cada tipo de pedido tem um teste de texto: a primeira
  frase tem no máximo 140 caracteres e não começa com emoji nem símbolo.
- **Relógio injetado** nos testes de prazo, lembrete e expiração.

## 7. Invariantes (cada uma com teste)

- **A-I1 – Só a pessoa decide.** Uma resposta de outra pessoa (outro
  usuário, outro chat, o mesmo grupo) nunca decide um pedido. Uma saída do
  modelo também não: só mensagens e interações de entrada da pessoa.
- **A-I2 – O primeiro texto é do código.** A primeira frase de todo pedido
  é gerada do pedido real (ferramenta, destino, ação), nunca do texto do
  modelo.
- **A-I3 – Um "sim" ambíguo não decide.** Com vários pendentes, só uma
  resposta com número decide; uma mensagem com qualquer outra palavra além
  do sim ou do não vai ao modelo e não decide.
- **A-I4 – Uma permissão vence.** Passado o prazo, o caso volta a perguntar;
  revogada, também.
- **A-I5 – "Sempre pergunta" não vira permissão.** O que o operador marcou
  assim nunca oferece prazo nem "sempre".

## 8. Épicos e etapas

### E20 — A resposta de qualquer jeito

#### E20.0: Linha de base

Conferir a seção 2 no master do dia; responder à dúvida do grupo (quem pode
decidir um pedido feito num grupo, em cada canal com grupo).

**Aceite:**
- [ ] `docs/relatorios/PRD-aprovacao-base.md`.
- [ ] Commit: `docs: PRD aprovação, linha de base`.

#### E20.1: Reconhecer a resposta

`domain/approval_reply_pure`: de um texto, `sim`/`não`/`sim N`/`não N`/
`sim sempre`/`sim 1 hora`/`sim 24 horas`, ou nada (A1, A2, A7).

**Aceite:**
- [ ] Tabela de testes com as palavras, acentos, caixa, pontuação e o que
      não é resposta ("sim, mas antes me diz…").
- [ ] Commit: `feat(aprovacao): reconhecer sim e não`.

#### E20.2: O sim que não vai ao modelo

`tryHandleApprovalInput` usa E20.1: com um pendente, decide; com vários e
sem número, lista; sem pendente, não intercepta nada.

**Aceite:**
- [ ] A-I1 e A-I3 testados em canal com botões (Telegram) e sem (IRC).
- [ ] Commit: `feat(aprovacao): sim e não por texto`.

#### E20.3: A voz decide

Depois da PRD Mídia E18.1: a transcrição de uma nota de voz passa pelo
mesmo reconhecimento antes de ir ao modelo (A3).

**Aceite:**
- [ ] Nota de voz transcrita "sim" decide; "sim, e manda também…" não.
- [ ] Commit: `feat(aprovacao): uma nota de voz decide`.

#### E20.4: O texto que se ouve

A primeira frase do código (A4), por ferramenta: `bash`, escrita de
arquivo, GitHub, A2A, MCP; numeração com vários pendentes.

**Aceite:**
- [ ] A-I2 e o gate de leitor de tela testados para cada tipo.
- [ ] Commit: `feat(aprovacao): o pedido começa pelo essencial`.

#### E20.5: Do grupo para o privado

A6, nos canais com grupo e privado.

**Aceite:**
- [ ] O pedido chega no privado; o grupo lê só o aviso; A-I1 no grupo.
- [ ] Commit: `feat(aprovacao): pedido de grupo vai ao privado`.

#### E20.6: Esperar sem travar

Conforme a decisão A5. Se (b): pedido pendente até 24 h, lembrete às 3 h,
autorização de uso único, a mensagem "[Aprovação #N] aprovada" à agente, o
passo refeito; persistência que sobrevive ao reinício.

**Aceite:**
- [ ] Ciclo inteiro com relógio de teste (lembra, expira, aprova tarde).
- [ ] Sobrevive a reinício.
- [ ] Commit: `feat(aprovacao): o pedido espera a pessoa`.

### E21 — Permitir por mais tempo

#### E21.1: Permissão com prazo

`StandingApprovalPort` ganha prazo (A7); o store grava o vencimento; `has`
passa a conferir o relógio.

**Aceite:**
- [ ] A-I4 testado; as permanentes atuais continuam sem prazo.
- [ ] Commit: `feat(aprovacao): permissão com prazo`.

#### E21.2: Que casos admitem

As chaves de A8 (ferramenta, repositório e ação, agente A2A) e a regra de
A-I5.

**Aceite:**
- [ ] A-I5 testado com a política `ask` do GitHub.
- [ ] Commit: `feat(aprovacao): permissões por ferramenta, repositório e agente`.

#### E21.3: `/permissoes`

Listar e revogar no chat (A9); a agente pode revogar quando a pessoa pede,
por uma ferramenta que só revoga.

**Aceite:**
- [ ] Nenhum caminho do modelo concede uma permissão (teste varre as
      ferramentas).
- [ ] Commit: `feat(aprovacao): /permissoes no chat`.

#### E21.4: Documentação

`docs/topics/` (aprovações e comandos): como responder, prazos, o que nunca
vira permissão.

**Aceite:**
- [ ] Commit: `docs: aprovação acessível`.

## 9. Riscos

- **Um "sim" que era conversa.** Com um pendente, "sim" sem mais nada decide.
  A regra é estreita (só a palavra, nada mais), e a resposta da agente
  confirma em voz alta o que foi aprovado.
- **A5 (b) muda o turno.** Um passo refeito depois de horas pode encontrar o
  mundo diferente (o arquivo mudou, a issue fechou). A agente refaz o passo
  inteiro, com as checagens, em vez de reaproveitar o resultado antigo.
- **Permissão esquecida.** O prazo padrão é a hora (o "sim" simples não cria
  permissão); "sempre" é escolha explícita e aparece em `/permissoes`.
