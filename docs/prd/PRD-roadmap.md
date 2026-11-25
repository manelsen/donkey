# PRD — Roadmap de 25/11/2026

Status: aprovado nas decisões de 25/11/2026 (ver [`docs/ROADMAP.md`](../ROADMAP.md)).
Um épico por frente, na ordem de execução. Cada história vira um PR, com
TDD, suíte completa verde e o caminho real do daemon testado.

---

## E1 — Retomada de turno após queda

**Problema.** Se o daemon cai no meio de um turno (reinício, OOM, deploy), a
mensagem fica sem resposta e ninguém sabe disso.

**Decisão.** Ao subir, um turno inacabado é refeito do início se nenhuma
ferramenta com efeito rodou. Se rodou, o usuário recebe um aviso com o que já
foi feito e a pergunta se deve continuar. O journal antigo nunca chegou ao
daemon (foi apagado como código inalcançável em `bf4778d1`); este é um desenho
novo e mínimo.

**Histórias**
- **E1.1 Journal mínimo (puro + store).** Três eventos por turno, gravados num
  arquivo privado em `state/`: início (id da mensagem, usuário, canal, destino
  de resposta, payload da sessão), efeito (uma ferramenta com efeito rodou:
  escrita, shell, envio, agendamento; a classificação que as aprovações já
  usam) e fim. Compactação junto com a do ledger.
  *Aceite:* um turno normal deixa início e fim; um com `fs_write` deixa também
  o efeito; o arquivo é 0600; a compactação descarta turnos encerrados.
- **E1.2 Ligado ao orquestrador.** O turno grava início antes da primeira
  chamada ao provider, efeito **antes** de executar a primeira ferramenta com
  efeito (write-ahead: uma queda entre o registro e a execução só faz o turno
  ser tratado como tendo efeito, nunca o repete) e fim depois da entrega final
  (ou do erro explicado). Basta o primeiro efeito: qualquer efeito já impede a
  retomada automática.
  *Aceite:* teste no orquestrador para cada caminho (resposta, erro de
  provider, parada pelo usuário, que conta como fim).
- **E1.3 Retomada na subida.** Na inicialização, para cada turno sem fim: sem
  efeito, ele volta à fila da sessão do usuário como se a mensagem tivesse
  acabado de chegar; com efeito, o usuário recebe "fui interrompido enquanto
  respondia a ‹início da mensagem›; já tinha feito ‹ferramentas›. Quer que eu
  continue?". Turnos de agendamento e heartbeat não são retomados (eles se
  repetem); turnos mais velhos que um limite (24 h) só geram o aviso.
  *Aceite:* teste de ponta a ponta com o daemon reconstruído sobre o mesmo
  `state/`; nenhuma ferramenta com efeito roda duas vezes.

**Fora:** retomar do meio do turno (rodada de ferramentas); isso exigiria
reexecução idempotente de ferramentas.

---

## E2 — Canal Microsoft Teams

**Problema.** Há usuários em Teams e o Donkey não tem o canal.

**Antes de codar:** ler a documentação atual do Bot Framework / Azure Bot
Service (registro single-tenant ou multi-tenant, endpoints de token e de
OpenID, formato de `Activity`) e citar no PRD da história, como foi feito
para Alibaba e Azure.

**Histórias**
- **E2.1 Verificação do JWT de entrada (pura + BearSSL).** O Bot Framework
  assina cada POST com um JWT RS256. Validar emissor, audiência (o App ID),
  validade e a assinatura com a chave do documento OpenID do Bot Framework
  (cache com TTL e recarga quando aparece um `kid` desconhecido). A
  verificação RSA usa o BearSSL que já está linkado (sem dependência nova).
  *Aceite:* vetores de teste RS256 conhecidos; token vencido, de outra
  audiência ou com assinatura errada recusado (401).
- **E2.2 Rota no receptor compartilhado.** `/webhook/teams`: `Activity` de
  mensagem vira evento na fila do canal (texto, remetente, conversa,
  `serviceUrl`, resposta citada para o contexto de resposta); demais tipos
  (typing, conversationUpdate) ignorados ou tratados como boas-vindas.
  *Aceite:* testes de rota no estilo de `t_webhook_cn_routes`.
- **E2.3 Envio.** Token de app (client credentials) com cache até expirar;
  `POST {serviceUrl}/v3/conversations/{id}/activities`, respostas em thread,
  Markdown do Teams, divisão de mensagens longas. Allowlist de egress para os
  hosts do Bot Framework.
  *Aceite:* teste com servidor falso; token renovado após expirar.
- **E2.4 Identidade e comandos.** `ckTeams` em todos os `case`, resolvedor de
  identidade, política de DM, `/continue` para ligar à identidade existente,
  doctor e assistente de configuração.
  *Aceite:* um usuário do Teams fala com o agente e liga sua identidade à de
  outro canal.

---

## E3 — Multi-bot (fachada)

**Problema.** Uma instância atende um bot por canal. Equipes querem vários bots
(personas e modelos diferentes) sem rodar várias instâncias.

**Decisão.** Cada bot tem token, nome, persona e modelo próprios; usuários,
memória e sessões são os da instância (a mesma pessoa falando com dois bots é
um usuário só, como os agentes nomeados).

**Desenho.** Configuração em `donkey.toml`:

```toml
[[bots]]
name      = "suporte"
channel   = "telegram"
token_env = "TELEGRAM_TOKEN_SUPORTE"   # Telegram, Discord
agent     = "suporte"                  # {home}/agents/suporte.toml

[[bots]]
name            = "vendas"
channel         = "whatsapp"
phone_number_id = "1234567890"         # WhatsApp: o número na mesma conta
agent           = "vendas"
```

- **Persona do operador.** Os agentes nomeados de hoje são do usuário (no
  paddock). A persona de um bot é decisão do operador e vale para todos: um
  agente da instância em `{home}/agents/<agente>.toml`, no mesmo formato
  (persona, provider, modelo). Um bot sem agente responde com a persona
  padrão.
- **Afinidade.** A sessão é do usuário e os turnos são em série: o bot pelo
  qual a pessoa escreveu por último é o que responde. Cada canal mantém a
  afinidade usuário → bot, atualizada a cada mensagem recebida, e tudo o que
  sai para aquela pessoa naquele canal (envio, edição do streaming, teclados,
  reações, digitação, download de anexos) vai pelo adapter desse bot. Duas
  mensagens seguidas para bots diferentes já viram um turno só no debounce.
  Lembretes e agendamentos saem pelo último bot usado; depois de um
  reinício, pelo bot padrão até a pessoa escrever de novo.
- **Mensagem.** `InboundMessage` carrega o nome do bot; o payload da sessão
  também, e o turno aplica a persona do bot quando a mensagem não começa com
  `@agente` (que continua valendo).
- O bot padrão (as variáveis de hoje) continua funcionando sem `[[bots]]`.

**Histórias**
- **E3.1 Modelo de bot e configuração.** Tipos, leitura do `[[bots]]`,
  validação (token ausente, agente inexistente, nome repetido), doctor.
- **E3.2 Bot na mensagem e na persona.** `InboundMessage` e o payload da
  sessão levam o bot; o turno aplica o agente da instância do bot (persona e
  modelo); a afinidade de cada canal leva a resposta pelo adapter certo.
- **E3.3 Telegram multi-bot.** Um long poll por token no executor; um adapter
  por bot.
- **E3.4 Discord multi-bot.** Uma conexão de gateway por token na
  infraestrutura de conexão permanente.
- **E3.5 WhatsApp multi-bot.** Vários números na mesma conta: o filtro por
  `phone_number_id` (#181) vira roteamento para o bot do número.
- **E3.6 Teams multi-bot** (depois de E2): vários App IDs na mesma rota.

*Aceite geral:* dois bots do mesmo canal na mesma instância, cada um
respondendo com sua persona e modelo; o mesmo usuário reconhecido nos dois.

---

## E4 — Kanban mínimo

**Problema.** Não há onde o agente e as pessoas acompanhem tarefas juntos.

**Decisão.** Um quadro sem UI: ferramenta, comando e atribuição a agentes
nomeados.

**Histórias**
- **E4.1 Domínio.** Tarefa com id, título, estado (`a fazer`, `fazendo`,
  `bloqueada`, `feita`), responsável (o usuário ou `@agente`), prazo opcional e
  notas; transições válidas; persistência no paddock (`TASKS.md` legível, como
  os demais `.md`).
- **E4.2 Ferramenta `manage_tasks`.** Criar, listar (com filtros), mover,
  atribuir, comentar, fechar. Negada a sub-agentes e a agentes consultados.
- **E4.3 Comando `/tasks`.** Lista o quadro no canal (agrupado por estado) com
  botões onde o canal tem teclado.
- **E4.4 Tarefas de agentes.** Uma tarefa atribuída a `@agente` com prazo vira
  lembrete para o agente, que a retoma num turno agendado e registra o
  andamento na tarefa.

**Fora (por ora):** quadro compartilhado entre usuários da instância.

---

## E5 — MCP sampling com aprovação

**Problema.** Servidores MCP que pedem amostragem (`sampling/createMessage`)
não funcionam com o Donkey.

**Decisão.** Cada pedido pede aprovação do usuário; a aprovação pode ser fixada
por servidor.

**Achado (25/11/2026).** As chamadas MCP são síncronas e rodam no laço do
daemon: enquanto um servidor MCP responde, todos os canais param. O sampling
com aprovação travaria (o servidor pede a amostragem no meio de uma chamada,
e a aprovação da pessoa precisa do laço). Daí a E5.0.

**Histórias**
- **E5.0 Cliente MCP stdio assíncrono.** O processo do servidor pelo
  `asyncproc` do Chronos; a chamada vira `invokeAsync` (o ToolAgent já a
  aguarda sem bloquear), um lock por cliente (ele é compartilhado entre
  sessões), prazo por chamada, e o laço de RPC que responde a pedidos do
  servidor e ignora notificações enquanto espera a própria resposta. A
  lista de ferramentas é pedida com `await` na subida. O cliente HTTP fica
  como está nesta etapa; o sampling começa pelo stdio.
- **E5.1 Protocolo.** O cliente MCP (stdio e Streamable HTTP) anuncia a
  capacidade `sampling` e atende o pedido do servidor: mensagens, preferências
  de modelo, `maxTokens`; a chamada vai pela rota do usuário, sem ferramentas.
- **E5.2 Aprovação.** O pedido vira um cartão no canal do usuário: "o servidor
  ‹nome› quer usar o modelo: ‹resumo do pedido›", com **aprovar uma vez**,
  **sempre para este servidor** e **negar**. "Sempre" fica registrado no
  `tools.toml` do servidor, ligado à identidade dele (o comando e argumentos,
  ou a URL), não só ao nome: se a identidade muda, a aprovação cai. Pode ser
  revogado por comando e pela TUI.
  Sem resposta no prazo: negado.
- **E5.3 Limites e registro.** Teto de tokens por pedido e por dia por
  servidor; cada pedido aparece no traço do turno e nas métricas.

---

## E6 — Gestão pela TUI

**Problema.** A TUI mostra configuração, agentes, canais, providers, modelos,
usuários e agendamentos, mas não deixa agir; a gestão é por `donkey ctl`.

**Histórias**
- **E6.1 Usuários.** Aprovar pareamentos, editar a allowlist de DM, ver os
  canais ligados de cada usuário.
- **E6.2 Agentes nomeados.** Criar, editar persona, provider e modelo, apagar.
- **E6.3 Agendamentos.** Pausar, retomar, apagar, ver a próxima execução e as
  perdidas.
- **E6.4 Traços e saúde.** Os traços recentes (filtro por usuário e período),
  o estado dos providers e das conexões permanentes.
- **E6.5 Aprovações de sampling e MCP** (depois de E5): ver e revogar as
  aprovações permanentes por servidor.

*Aceite geral:* cada ação feita pela TUI tem o mesmo efeito do `ctl`
correspondente e é testada pela mesma função pura.

---

## Ordem e dependências

E1 → E2 → E3 (E3.6 depois de E2) → E4 → E5 → E6 (E6.5 depois de E5).
E4 e E5 não dependem de E3 e podem andar em paralelo a ela se for útil.
