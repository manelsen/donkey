[PRD]
# PRD Proatividade: o agente que puxa assunto, sem virar ruído

> **Situação em 27/11/2026:** rascunho. As decisões marcadas **[proposta]**
> são padrões sugeridos que o mantenedor confirma. **P2** decidida em
> 27/11: desligada por padrão na instância; cada pessoa entra.
>
> **Depende de:** agendamentos e lembretes, heartbeat, quadro de tarefas
> (E4), memória MAGMA, `web_search`, o modelo auxiliar da revisão em segundo
> plano (E7.4), todos no master. Usa a [PRD Aprovação acessível](PRD-aprovacao-acessivel.md)
> só para lembrar de um pedido esquecido (E23.2).

> **Executor:** agente autônomo. Leia este documento inteiro antes de
> começar. Execute as etapas **na ordem**. Cada etapa termina com os quality
> gates verdes e um commit próprio. **Não improvise decisões.**

## 1. Visão

Um assistente que só fala quando é chamado espera demais de quem o usa:
lembrar de chamar, saber o que perguntar. Numa equipe pequena, isso aparece
como o prazo que ninguém lembrou, a issue que a pessoa estava acompanhando e
que mudou, o assunto que ela estudava e que ganhou uma novidade.

O Donkey passa a **puxar assunto**: algumas vezes por dia, ele olha o que
importa para a pessoa (o que ela pediu para acompanhar, o que conversaram, o
que vence) e, se valer a pena, manda uma mensagem curta, que começa pelo
essencial e termina numa pergunta fácil de responder.

Ser proativo não pode virar ruído, invasão nem risco ao canal. **As regras
do código são o teto; o modelo decide dentro dele.**

## 2. Contexto (conferido em 27/11/2026 no master `81f0c854`)

- **O proativo combinado já existe:** agendamentos (cron, intervalo, uma
  vez) e lembretes mandam mensagem na hora marcada, quando a pessoa pediu.
- **O heartbeat** (`app/heartbeat.nim`) lê o `HEARTBEAT.md` de cada paddock
  e despacha as tarefas não marcadas como um turno ("Heartbeat
  automático…"), com um intervalo mínimo por pessoa. É uma lista que a
  pessoa escreve; não escolhe assunto nem decide se vale falar.
- **Quadro de tarefas** (`manage_tasks`, `/tasks`, E4): tarefas com prazo;
  uma tarefa de agente vira turno dele no dia.
- **O que o Donkey sabe da pessoa:** `USER.md`, `PREFERENCES.md`, a memória
  MAGMA (grafo com tempo e entidades), as conversas antigas (busca), o
  Backtrail.
- **Modelo auxiliar:** a revisão em segundo plano (E7.4) já usa um modelo
  barato separado do da conversa.
- **Restrição de canal:** no WhatsApp (Cloud API, oficial), uma mensagem
  iniciada pelo Donkey **fora da janela de 24 h** desde a última mensagem da
  pessoa só pode ser um *template* aprovado pela Meta. Nos demais canais não
  há regra parecida, mas há regras de bom uso (Slack e Teams punem bots
  ruidosos com a desinstalação).
- **No Supernova (PRD-Q, rascunho de 27/11):** eventos fixos (prazos,
  consultas, tarefas, aprovações esquecidas) e fluidos (temas da conversa);
  até 3 por dia, adaptativo entre 1 e 6; nunca duas seguidas sem resposta;
  silêncio das 22 h às 8 h; um modelo barato decide se fala; assuntos
  sensíveis configuráveis por pessoa.

## 3. Decisões

| # | Decisão |
|---|---|
| P1 | **[proposta]** **Dois gatilhos.** *Fixos:* um prazo do quadro ou um lembrete que vence amanhã, uma tarefa de agente que terminou, uma aprovação pendente há horas. *Fluidos:* temas da conversa e o que a pessoa pediu para acompanhar ("me avisa se essa issue andar"). |
| P2 | **Decidida (mantenedor, 27/11): desligada por padrão na instância; cada pessoa entra.** O Supernova liga por padrão (companhia). Num assistente de equipe, **recomendação: desligada por padrão na instância** (`[proactive] enabled = false`), e, quando o operador liga, **cada pessoa entra com `/proativo sim`** ou recebe um convite único para entrar. |
| P3 | **[proposta]** **Quanto:** até **2 mensagens fluidas por dia** por pessoa no começo; **nunca duas seguidas sem resposta** (a próxima fluida espera a pessoa falar); o teto aprende entre **1 e 4** com as respostas; os fixos não contam no teto. `/proativo mais` e `/proativo menos` ajustam. |
| P4 | **[proposta]** **Quando:** só no **horário de trabalho da pessoa**, no fuso dela (`USER.md`), padrão **9 h às 18 h, dias úteis**; configurável por pessoa (`/proativo horario 8-17`). Fora dele, nem os fixos (ficam para a abertura da próxima janela). |
| P5 | **[proposta]** **Quem decide:** o código abre a janela (P3, P4, a última sem resposta, o canal permite); dentro dela, o **modelo auxiliar** responde "vale falar agora? sobre o quê?" e pode dizer que não; o texto sai do modelo da conversa, na voz do Donkey. |
| P6 | **[proposta]** **Assuntos sensíveis** (saúde, vida pessoal, desempenho, dinheiro): por padrão o Donkey **não volta a eles por conta própria**; a pessoa libera (`/proativo assuntos livres`). |
| P7 | **[proposta]** **Canal:** a proativa vai ao canal em que a pessoa falou por último, no privado. No WhatsApp, só dentro da janela de 24 h; fora dela, espera a pessoa falar (nada de template nesta PRD). |
| P8 | **[proposta]** **Custo:** as proativas de uma pessoa cabem num teto diário (padrão US$ 0,05), contado como os turnos; acima dele, nenhuma fluida no dia. |

## 4. O que a pessoa vive

- Terça, 10h: "A issue 214 do acme/site, que você pediu para acompanhar,
  ganhou um PR de correção agora há pouco. Quer que eu resuma?"
- Quarta, 17h: "Amanhã vence a entrega do relatório trimestral, no quadro
  da equipe. Quer que eu te lembre de manhã?"
- Ela não respondeu à de terça: na quinta, nada de novo até ela falar (a de
  quarta era um prazo, fixo, e foi).
- "Para de me mandar mensagem sozinho": o Donkey desliga e confirma numa
  frase; `/proativo sim` religa.

## 5. Fora de escopo

- Mensagens proativas em grupo.
- Templates do WhatsApp.
- Agir por conta própria (publicar, enviar e-mail) sem pedido.
- Proativas em voz (`/voz`) na primeira versão.

## 6. Quality gates

Os de sempre (`CLAUDE.md`). Mais:

- **Relógio e fuso injetados** em todo teste de janela.
- **O decisor é testado com respostas gravadas** do modelo auxiliar (sim,
  não, assunto sensível), nunca com o modelo real.

## 7. Invariantes (cada uma com teste)

- **P-I1 – Fora da janela, nada.** Nenhuma proativa fora do horário da
  pessoa, com a proatividade desligada (instância ou pessoa), acima do teto
  do dia ou acima do teto de custo.
- **P-I2 – Nunca duas fluidas seguidas sem resposta.**
- **P-I3 – Só conversa.** Uma proativa nunca chama ferramenta com efeito
  fora da máquina nem abre pedido de aprovação; pode pesquisar e ler.
- **P-I4 – Assunto fechado não volta.** Com P6 no padrão, nenhuma fluida
  menciona um tema marcado sensível; o teste usa conversas marcadas.
- **P-I5 – O canal manda.** No WhatsApp, nenhuma proativa fora da janela de
  24 h.

## 8. Épicos e etapas

### E22 — O relógio e as regras

#### E22.0: Linha de base

Conferir a seção 2; medir quantas pessoas, canais e fusos há numa instância
típica; listar o que o heartbeat já faz por pessoa.

**Aceite:**
- [ ] `docs/relatorios/PRD-proatividade-base.md`.
- [ ] Commit: `docs: PRD proatividade, linha de base`.

#### E22.1: A janela

`domain/proactive_pure`: dado o relógio, o fuso, as preferências, o teto, o
gasto do dia e a última proativa (respondida ou não), a janela está aberta?
Para fixos? Para fluidas?

**Aceite:**
- [ ] P-I1, P-I2 e P-I5 testados na função pura, com tabela de casos.
- [ ] Commit: `feat(proativo): a janela de cada pessoa`.

#### E22.2: O relógio por pessoa

Um laço no heartbeat (não um novo) que, a cada volta, avalia a janela de
cada pessoa; o estado (última proativa, respondida, teto atual) sobrevive
ao reinício.

**Aceite:**
- [ ] Sobrevive a reinício; relógio de teste.
- [ ] Commit: `feat(proativo): o relógio por pessoa`.

#### E22.3: Comandos e preferências

`/proativo sim|não|mais|menos|horario|assuntos`, no `PREFERENCES.md`;
P2 na instância (`[proactive]` no `donkey.toml`).

**Aceite:**
- [ ] Desligar por frase ("para de me mandar mensagem sozinho") chega à
      agente, que chama o mesmo comando.
- [ ] Commit: `feat(proativo): ligar, desligar e ajustar`.

#### E22.4: Métricas

Janelas abertas, proativas mandadas, respondidas, ignoradas, por tipo.

**Aceite:**
- [ ] No Prometheus e no `/insights`.
- [ ] Commit: `feat(proativo): métricas`.

### E23 — Os gatilhos fixos

#### E23.1: Prazos

Um prazo do quadro ou um lembrete que vence no dia útil seguinte vira
gatilho fixo, uma vez.

**Aceite:**
- [ ] Commit: `feat(proativo): prazo que vence amanhã`.

#### E23.2: Aprovação esquecida

Um pedido pendente há mais de 3 h (com a PRD Aprovação, A5 (b)) vira
gatilho fixo, uma vez.

**Aceite:**
- [ ] Commit: `feat(proativo): aprovação esquecida`.

#### E23.3: Tarefa de agente terminada

O resultado de uma tarefa de agente do quadro, quando a pessoa não estava na
conversa, é avisado.

**Aceite:**
- [ ] Commit: `feat(proativo): tarefa terminada`.

### E24 — Puxar assunto

#### E24.1: O que acompanhar

"Me avisa se…" vira um acompanhamento guardado na memória da pessoa
(entidade `commitment` do MAGMA), com o que olhar (uma issue, um tema, uma
página) e até quando.

**Aceite:**
- [ ] Listar e cancelar pelo chat.
- [ ] Commit: `feat(proativo): o que acompanhar`.

#### E24.2: O decisor

Na janela de fluidas, o modelo auxiliar recebe os acompanhamentos, os temas
recentes e os assuntos fechados, e responde em JSON: falar ou não, sobre o
quê, o que pesquisar. Contra respostas gravadas.

**Aceite:**
- [ ] P-I4 testado.
- [ ] Commit: `feat(proativo): o decisor`.

#### E24.3: Pesquisar e escrever

Se fala: a pesquisa (`web_search`, `github` só leitura, a memória) com teto
de custo (P8), e a mensagem pelo modelo da conversa: curta, o essencial
primeiro, termina numa pergunta.

**Aceite:**
- [ ] P-I3 testado (ferramentas com efeito ficam fora da lista).
- [ ] Commit: `feat(proativo): puxar assunto`.

#### E24.4: Aprender

Resposta, demora e tom de cada fluida ajustam o teto (P3) e os temas que
funcionam para a pessoa.

**Aceite:**
- [ ] Commit: `feat(proativo): aprender com as respostas`.

#### E24.5: Documentação

`docs/topics/` (proatividade e comandos): o que dispara, os tetos, como
desligar, o WhatsApp.

**Aceite:**
- [ ] Commit: `docs: proatividade`.

## 9. Riscos

- **Ruído.** O teto baixo, o "nunca duas sem resposta" e o aprendizado para
  baixo; e P2: desligada por padrão, cada pessoa entra.
- **Invasão.** A mesma frase é cuidado para uma pessoa e intromissão para
  outra. P6 conservador por padrão, configurável por pessoa.
- **Custo.** Cada janela que decide falar pesquisa e escreve; o modelo
  auxiliar na decisão e o teto em US$ (P8) limitam.
- **Desinstalação.** Em Slack e Teams, um bot ruidoso é removido pela
  equipe; as métricas (E22.4) mostram a taxa de resposta antes disso.
