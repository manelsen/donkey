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
  *Depois:* o cliente HTTP manda cada POST ao executor de bloqueantes, e os
  skills Deno usam o cliente assíncrono, um por skill para o processo todo,
  listados em segundo plano (um skill novo aparece a partir da mensagem
  seguinte).
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

*Feito.* E6.2 cuida dos agentes da instância (`{home}/agents`, as personas
dos bots): `N` abre um formulário, `Enter` edita, `D` apaga, pela mesma
operação de `manage_agents`. Os agentes de cada usuário continuam com o
próprio usuário, pela ferramenta. E6.4 mostra, na seção de providers, as
chamadas, a latência e o cooldown da janela recente do daemon. O estado de
conexão de cada canal não está no status do daemon, e a seção de canais
mostra os ativos.

---

## E7 — Auto-aprimoramento

**Problema.** O Donkey lembra fatos (MAGMA), mas não aprende procedimentos:
o que funcionou numa tarefa não vira um modo de fazer reaproveitável, e
nada revisa o que foi aprendido. O Hermes tem um ciclo completo: skills em
Markdown que o agente escreve e corrige, revisão em segundo plano depois dos
turnos, um curador que consolida, e a jornada do que foi aprendido.

**Decisões (26/11).** Skills por pessoa, no paddock; revisão com um modelo
auxiliar barato configurável; guarda que bloqueia antes de gravar.

**Histórias**
- **E7.1 Skills aprendidas.** O formato `SKILL.md` (frontmatter com nome de
  1–64 caracteres a-z, 0-9 e '-' e uma descrição de até 1024; instruções
  depois), guardado em `{paddock}/learned_skills/<nome>/`, com proveniência
  (quem criou, quando, a partir de quê). A guarda, com categorias e padrões
  do Hermes (MIT), bloqueia exfiltração de segredos, injeção de prompt,
  caracteres invisíveis e comandos destrutivos; o bloqueado não é gravado e
  o motivo volta. Arquivar move para `.archive/`; nada é apagado.
- **E7.2 Ferramentas.** `skill_manage` (create, edit, patch, archive,
  restore) e `skill_view`; o índice das skills (nome e descrição) entra no
  prompt de sistema, e uma skill criada no meio da sessão chega como nota.
- **E7.3 Uso.** Cada carga de skill conta; o curador e a jornada leem.
- **E7.4 Revisão em segundo plano.** Depois de N turnos de usuário ou de M
  rodadas de ferramenta, uma cópia do agente com a rota auxiliar relê a
  conversa e só pode usar `skill_manage` e a memória; fora do laço, sem
  tocar a sessão.
- **E7.5 `/refine` e `/learn`.** A revisão agora; uma fonte (texto, URL,
  "o que acabamos de fazer") vira skill pelo próprio agente.
- **E7.6 Curador.** Quando a pessoa está inativa e o último passe é antigo:
  arquiva o que não é usado há muito tempo e consolida duplicatas por uma
  cópia do agente; nunca apaga; backup antes de mudar, com rollback.
- **E7.7 Jornada.** `donkey ctl skills learned <uuid>`, a seção na TUI e
  `/skills learned` para a pessoa: listar, ver, arquivar, restaurar.
- **E7.8 Insights.** `/insights`: ferramentas e skills mais usadas, tokens
  e custo estimado, dos traços e métricas.

*Aceite geral:* nada aprendido com uma pessoa aparece para outra; toda
gravação de skill passa pela guarda; a revisão nunca segura o laço nem muda
a sessão em curso.

*Feito (26/11, #220–#228).* As oito histórias. Desvios do plano: a revisão
cuida só de skills (os fatos ficam com o MAGMA); o índice entra no prompt a
cada turno, sem a nota de diferença do Hermes (que existe para preservar o
cache de prompt, que o Donkey não usa); `/insights` é `donkey ctl insights`,
sem custo; a jornada é texto; promover uma skill para todas as pessoas não
foi feito. Tudo no §3 do roadmap.

---

## Quarta rodada (proposta em 26/11, aguardando aprovação)

Seis épicos, em ordem de ganho. Os números de API citados abaixo são da
documentação dos providers em 26/11 e serão conferidos na implementação.

---

## E8 — Cache de prompt

**Problema.** O Donkey não usa cache de prompt: a cada turno, e a cada
rodada de ferramenta dentro do turno, o provider recebe e cobra o contexto
inteiro (prompt de sistema, esquemas das ferramentas, histórico). Numa
conversa longa com ferramentas, a maior parte do que se paga é texto que o
provider acabou de ver. O cache cobra só uma fração por esse prefixo repetido
e reduz o tempo até o primeiro token. O Hermes já faz isso (aquece o cache,
compacta antes de ele expirar, aprende como cada rota cacheia).

**Como o cache funciona (o que o desenho precisa respeitar).**
- É casamento de prefixo, byte a byte. Na Anthropic a ordem é ferramentas →
  sistema → mensagens; qualquer byte diferente invalida tudo o que vem
  depois. Um horário, uma lembrança recuperada ou o índice de skills no meio
  do prompt de sistema anulam o cache a cada turno.
- **Anthropic** (e Bedrock, e OpenRouter para modelos `anthropic/*`):
  - Marcação explícita: `cache_control: {type: "ephemeral"}` num bloco, até
    4 marcadores. Também existe o modo automático (`cache_control` no topo do
    pedido), que marca o último bloco e avança com a conversa.
  - Prefixo mínimo por modelo: 512 tokens nos modelos 5.x e até 4096 em
    alguns antigos. Um prefixo menor não cacheia e não dá erro.
  - Escrita custa 1,25× a entrada (TTL de 5 minutos) ou 2× (TTL de 1 hora).
  - Leitura custa cerca de 0,1× (0,05× no Opus 5.5 e no Sonnet 5.5).
  - O uso vem em `cache_creation_input_tokens` e `cache_read_input_tokens`;
    `input_tokens` é só o resto não cacheado.
- **Caches automáticos, sem marcador:** OpenAI, DeepSeek e Gemini (implícito)
  cacheiam sozinhos prefixos estáveis e informam no uso (respectivamente
  `prompt_tokens_details.cached_tokens`, `prompt_cache_hit_tokens` e
  `cachedContentTokenCount`). Para eles, o ganho vem só de o prefixo ser
  estável.

**Histórias**
- **E8.1 Prefixo estável.** Separar o que não muda (persona, regras,
  instruções das ferramentas, esquemas em ordem determinística) do que muda a
  cada turno (lembranças do MAGMA e do Backtrail, índice de skills, data e
  hora, notas da sessão). O volátil passa para depois do prefixo, como último
  bloco do sistema ou junto da mensagem do turno. Mapear antes como o
  histórico é limitado: uma janela que desliza a cada turno também quebra o
  prefixo.
  *Aceite:* dois turnos seguidos da mesma sessão produzem pedidos cujo
  prefixo (ferramentas, sistema estável e histórico anterior) é idêntico byte
  a byte, verificado por teste puro sobre o pedido montado.
- **E8.2 Marcadores na Anthropic.** No dialeto Anthropic (adapter direto,
  Bedrock e OpenRouter com modelo `anthropic/*`): um marcador explícito no
  fim do sistema estável, mais o modo automático (ou um marcador no último
  bloco, onde o automático não existe) para a cauda da conversa. TTL
  configurável por rota (`cache_ttl = "5m" | "1h"`, padrão 5m).
  *Aceite:* nas rodadas de ferramenta de um mesmo turno, a segunda chamada
  em diante lê do cache (teste com resposta gravada e conferência manual com
  chave real).
  *Feito:* sem o modo automático (que endpoints compatíveis podem não
  aceitar), dois marcadores explícitos de 5 minutos: o fim do sistema e o
  último bloco da última mensagem. Anthropic só na API oficial (o endpoint
  compatível da Z.ai fica sem); Bedrock com `cachePoint`, só para modelos
  Claude; OpenRouter só para `anthropic/*`. O TTL de 1 hora por rota fica
  para quando a medição mostrar pausas maiores que 5 minutos.
- **E8.3 Tokens cacheados no uso.** `CompletionResponse` ganha `cacheRead` e
  `cacheWrite`, lidos de cada dialeto (Anthropic, OpenAI e compatíveis,
  DeepSeek, Gemini, Bedrock), também no streaming. Traços, métricas
  Prometheus e `/insights` passam a mostrar a taxa de acerto por rota.
  *Feito:* `cacheReadTokens` e `cacheWriteTokens` na resposta, de todos os
  dialetos, com e sem streaming; na Anthropic e no Bedrock, `inputTokens`
  passou a ser o prompt inteiro (antes era só o resto não cacheado). Traço,
  span OTLP, métrica (`direction="cache_read"`/`"cache_write"`) e `/insights`
  (parte da entrada servida pelo cache, por provider).
- **E8.4 Detector de invalidação.** Uma rota que cacheia mas lê zero do
  cache por N turnos seguidos numa mesma sessão gera um aviso no log e no
  `doctor`, com o tamanho do prefixo (pode ser só um prefixo abaixo do
  mínimo).
  *Feito:* dos traços, não do log: um provider com 5 ou mais prompts de
  2048 tokens ou mais e nenhuma leitura do cache aparece no `/insights` e no
  `doctor` (últimos 7 dias). Sem filtro por provider (o rótulo pode ser uma
  rota inteligente); o aviso cita as duas causas, provider sem cache ou
  começo do prompt que muda.
- **E8.5 Compactação.** Mapeado em 26/11: o histórico nunca encolhia (o
  `/compact` era um esboço; o módulo antigo foi apagado por não ter uso), e
  uma sessão longa acabaria passando do contexto do modelo. *Decisões
  (26/11):* compactar passado 40% do contexto de um modelo de 1M tokens e 60%
  de um menor; o resumo é escrito pelo modelo da sessão; módulo novo.
  *Feito:* no começo do turno, em degrau (nunca uma janela que desliza): a
  parte antiga vira um resumo e a cauda recente (um quarto do limite, a
  partir de uma mensagem da pessoa) fica como estava. Logo depois de um turno
  o cache está quente, então um histórico pouco acima do limite espera uma
  pausa de 5 minutos; 25% acima, compacta na hora. O tamanho do contexto vem
  do catálogo de modelos (128k quando desconhecido). `/compact` faz o mesmo
  passo sob pedido. Fica para depois, se a medição pedir: aquecer o cache
  (`max_tokens: 0`) antes de um agendamento.

*Aceite geral:* nenhuma mudança no que o modelo recebe, só na ordem; custo
por turno medido antes e depois numa conversa de referência com ferramentas.

*Decisões (26/11):* TTL padrão de 5 minutos; o volátil vai com a mensagem
do turno, num bloco `<turn_context>`. Primeiro só no pedido; corrigido no
mesmo dia: o bloco fica guardado com a mensagem a que pertence
(`turnContext`, fora do texto que vai para a transcrição) e segue com ela em
todo pedido, porque tirá-lo editava um turno anterior (os modelos novos
recusam, depois que os blocos de raciocínio voltam a ser enviados) e cortava
o cache. Também saiu o corte do histórico nas 20 mensagens mais recentes a
cada turno, que movia o começo do histórico; quem limita o histórico agora é
a compactação (E8.5). O pedido é só acréscimo: o cache lê o histórico
inteiro, entre turnos e entre rodadas.

---

## E9 — Mídia nos canais novos

**Problema.** Google Chat, Mattermost, SMS, IRC e Teams entraram só com
texto: uma foto, um áudio ou um PDF enviado ali não chega ao agente, e o
agente não manda arquivos de volta. Os canais antigos já fazem isso pelo
mesmo caminho (`mediaPaths` na entrada, anexos na saída, transcrição e
`inspect_image`).

**Decisão (26/11).** MMS só de entrada: o Donkey não serve arquivos por URL
pública (o que exigiria expor o endpoint HTTP do daemon); para mandar um
arquivo por SMS, responde com texto.

**Histórias**
- **E9.1 Mattermost.** Entrada: os `file_ids` do post são baixados pela API
  de arquivos. Saída: o anexo é enviado com `POST /files` e citado no post.
  *Feito:* entrada pelo `file_ids` e `metadata.files` do post (também na
  recuperação depois de uma queda), o primeiro arquivo até 25 MB baixado
  pelo `downloadFile` do canal, os outros nomeados; saída por upload
  (`POST /files`, multipart) e o id no post, lendo o arquivo só dentro do
  paddock (a leitura confinada saiu do Telegram para
  `adapters/filesystem/confined_read`).
- **E9.2 Google Chat.** Entrada: anexos da mensagem pela API de mídia, com o
  token da conta de serviço. Saída: upload de anexo; cartões (cardsV2) para
  pedidos de aprovação.
  *Feito (entrada):* `message.attachment[]`; o primeiro arquivo enviado
  (até 25 MB) é baixado por `media.download` com o token do app (escopo
  `chat.bot`); um arquivo do Drive (que o app não lê) e os outros são
  nomeados. *Saída:* não há: a documentação do Google diz que
  `media.upload` exige autenticação de usuário ("Requires user
  authentication"), então um app não manda arquivo. Os cartões de aprovação
  ficam para quando a aprovação (E11.3) for usada por canais.
- **E9.3 SMS → MMS, só de entrada.** `NumMedia` e `MediaUrlN` do webhook da
  Twilio, baixados com autenticação. Um anexo de saída vira texto (o nome e
  o que é), nunca uma URL.
  *Feito:* `MediaUrlN` e `MediaContentTypeN`; o primeiro item (até 25 MB)
  baixado só de uma URL de mídia da própria conta, com as credenciais e sem
  seguir redirecionamento; um redirecionamento para o armazenamento de mídia
  da Twilio é seguido sem elas. Os outros itens são citados pelo tipo; uma
  mensagem só com mídia vira turno. Os hosts do redirecionamento
  (`media.twiliocdn.com`, `mms.twiliocdn.com`, o S3 da Twilio) ficam para
  conferir com uma conta real.
- **E9.4 Teams.** Entrada: anexos (imagens inline e arquivos do OneDrive por
  `downloadUrl`). Saída: arquivos e Adaptive Cards para aprovações.
  *Feito (entrada):* um arquivo de conversa pessoal
  (`file.download.info`, URL pré-autenticada do SharePoint, sem token) ou
  uma imagem colada (URL do Bot Framework, com o token do bot); o primeiro
  chega ao turno, os outros são nomeados. O token só vai ao serviço do Bot
  Framework. *Fica:* mandar arquivo (no Teams pede um cartão de
  consentimento em conversa pessoal) e os Adaptive Cards de aprovação; com
  vários apps, a imagem é buscada com o token do app padrão.
  *Teams completo, partes 1 e 2 (pedido do mantenedor, 26/11: há demanda):*
  uma imagem PNG, JPEG ou GIF de até 1 MB vai embutida (data URI); outro
  arquivo, em conversa pessoal, por cartão de consentimento
  (`file.consent`), enviado por PUT ao OneDrive da pessoa quando ela aceita
  (`fileConsent/invoke`) e mostrado num cartão `file.info`; em grupo ou canal,
  uma nota. A resposta ao `invoke` é HTTP 200 sem corpo, a convenção dos SDKs
  (a documentação não mostra; conferir num tenant real). *Parte 3, feita:*
  `MICROSOFT_APP_CERT` (PEM com certificado e chave); com ele, todo download
  e upload de arquivo leva um token pedido por `client_assertion` (JWT RS256
  com o `x5t` do certificado, escopo `/.default` do host do arquivo,
  conferido contra o OpenSSL num certificado de teste); sem ele, funciona só
  até 1º/3/2027. Os apps de `[[bots]]` ainda não recebem certificado.
  *Falta:* a parte 4, os cartões de aprovação (`Action.Execute`,
  `invoke adaptiveCard/action`).
- **E9.5 IRC.** Só links: o protocolo não carrega arquivos (DCC fica fora).
  Na entrada, uma URL de imagem pode ir ao `inspect_image` por decisão do
  agente, como em qualquer canal.
- **E9.6 Ferramenta `send_file`.** Achado ao fazer E9.1: o único arquivo
  que sai hoje é a resposta em voz (e só onde há `sendVoice`); nenhuma
  ferramenta manda ao canal um arquivo do paddock. `send_file` manda um
  arquivo do paddock da pessoa para o canal da conversa, lido só dentro do
  paddock; onde o canal não aceita arquivo (`sendMedia`), responde com o
  nome e que ele está guardado. Sem ela, o upload do Mattermost (E9.1) só
  serve à voz.
  *Feito:* `send_file(path, caption)`; o caminho resolvido dentro do
  paddock; uma capacidade própria, `cfSendFile` (o adapter lê um arquivo do
  paddock e o sobe), verdadeira no Telegram e no Mattermost. Achado ao
  fazer: `sendMedia` não basta. O Discord ignora o `mediaUrl` no envio e o
  WhatsApp mandaria o caminho local como link; ficam sem a ferramenta até
  ganharem upload (continuação: Discord, Slack e WhatsApp com upload).
  *Atendido sem código:* uma URL que a pessoa manda já chega ao agente no
  texto, e a `send_file` no IRC responde com o caminho (o IRC não tem
  `cfSendFile`).

*Aceite geral:* uma foto e um áudio mandados em cada canal chegam ao agente
como nos canais antigos (teste com servidor falso por canal); limites de
tamanho por canal respeitados com mensagem clara.

---

## E10 — Interface para editores (ACP)

**Problema.** A maior distância restante do comparativo está em Interfaces
(72% contra 97% do Hermes). O Agent Client Protocol (ACP), usado pelo Zed e
por extensões de outros editores, deixa o editor conversar com um agente por
JSON-RPC sobre stdin e stdout: o editor abre sessões, manda prompts, recebe
a resposta em pedaços, vê as chamadas de ferramenta e responde a pedidos de
permissão.

**Decisões (26/11).** O editor é um canal: entra por pareamento, como os
outros (`ctl pair`), e a pessoa pareada é a mesma dos outros canais, com a
memória compartilhada.

**Histórias**
- **E10.1 `donkey acp`.** Um subcomando que fala ACP com o editor e repassa
  ao daemon pela IPC já existente (o mesmo caminho do `ctl` e da API
  compatível com OpenAI); nada de laço novo. `initialize`, `session/new`,
  `session/prompt`, `session/cancel`.
- **E10.2 Pareamento.** Na primeira vez, o editor mostra um código que a
  pessoa confirma num canal onde já é conhecida (ou o operador, com
  `ctl pair`); depois, o editor guarda uma credencial local e a sessão é da
  pessoa, com a memória dela.
- **E10.3 Streaming e ferramentas.** Pedaços da resposta como
  `session/update`; cada chamada de ferramenta aparece com título e estado.
- **E10.4 Aprovações.** Os pedidos de aprovação do Donkey (ferramentas
  perigosas, sampling) viram `session/request_permission` no editor.
- **E10.5 Contexto do editor.** Arquivos anexados ao prompt pelo editor
  entram como anexos do turno; leitura de arquivos pelo editor
  (`fs/read_text_file`) só se o editor oferecer e com aprovação.

*Aceite geral:* uma sessão no Zed, pareada, conversa com a pessoa que ela é
nos outros canais (lembra o que foi dito no Telegram), vê as ferramentas
rodando e aprova ou recusa uma ação perigosa.

---

## E11 — Escrita no GitHub com política

**Problema.** A ferramenta `github` só lê. Abrir uma issue, comentar num PR
ou numa issue e pôr um rótulo são pedidos comuns de equipe, e o Pincer já os
faz.

**Decisões (26/11).** Uma política por repositório diz que ações passam sem
perguntar e quais pedem aprovação; o token é de cada pessoa (o GitHub
registra quem agiu, e cada um só escreve onde já pode).

**Histórias**
- **E11.1 Ações de escrita.** `create_issue`, `comment` (issue ou PR),
  `add_labels`, `close_issue`; sem merge, push ou apagar.
- **E11.2 Token por pessoa.** Cada pessoa guarda o próprio token no cofre
  (`/github token` no chat, gravado como segredo da pessoa, nunca no
  histórico); sem token, a escrita é recusada com a instrução de como
  configurar. A leitura continua com o token da instância.
- **E11.3 Política por repositório.** No `donkey.toml`, por repositório (ou
  padrão): cada ação é `allow`, `ask` ou `deny`; o padrão é `ask` para tudo.
  `ask` usa o mecanismo de aprovação que já existe, mostrando o texto exato
  e onde será publicado.

*Aceite geral:* nada é publicado fora da política; o que pede aprovação só
sai aprovado, com o texto aprovado byte a byte; cada escrita sai com o token
de quem pediu.

---

## E12 — Supervisão de adapters (à maneira do OTP)

**Problema.** O Donkey compila com `--panics:on`: um `Defect` (índice fora
do limite, nil, asserção) em qualquer adapter derruba o daemon inteiro e
todos os canais com ele. A retomada de turno (E1) e o systemd limitam o
estrago, mas a queda é de todos. No Pincer, a árvore OTP reinicia só o
pedaço que falhou.

**Decisão (26/11).** Inspirar-se no modelo OTP: uma árvore de supervisão.
Em Nim, um `Defect` com panics ligado não pode ser capturado (nem numa
thread), então a árvore tem dois níveis de filho: a tarefa dentro do daemon
(para erros capturáveis) e o processo do sistema (para isolamento total).

**O que vem do OTP**
- *Árvore:* o daemon supervisiona os canais e os jobs; o systemd
  supervisiona o daemon, que retoma os turnos pelo journal (E1).
- *Estratégia `one_for_one`:* um filho que cai é reiniciado sozinho.
- *Tipos de filho:* `permanent` (canais: sempre reiniciados), `transient`
  (só se caírem com erro), `temporary` (jobs: nunca).
- *Intensidade:* no máximo N reinícios em T segundos (padrão 5 em 60); além
  disso, o supervisor escala: o canal fica `down` no status, o operador é
  avisado, e o daemon segue com os outros.
- *"Let it crash":* um adapter não guarda estado que importe; o que importa
  vive no journal, nas filas e na fila de mensagens mortas, então reiniciar
  não perde nada.

**Histórias**
- **E12.1 Mapa de riscos.** Onde um `Defect` pode nascer nos adapters
  (indexação de dados externos, `get` de `Option`, conversões) vira erro
  como valor; um teste de arquitetura impede a volta dos padrões mais
  perigosos nos parsers de canal.
- **E12.2 Supervisor no daemon.** A especificação de cada filho (tipo,
  intensidade, espera crescente entre reinícios), a estratégia
  `one_for_one` e a escalada; estado `restarting`/`down` no status e na TUI.
- **E12.3 Filho como processo.** Para os canais de socket (Discord,
  Mattermost, IRC), o filho pode ser um processo do sistema que fala com o
  daemon pela fila de eventos; o supervisor reinicia o processo pelas mesmas
  regras. Ligado por canal na configuração.

*Aceite geral:* um adapter que falha repetidamente não interrompe os outros
canais nem os turnos em curso; um `Defect` num canal que roda como processo
não derruba o daemon.

---

## E13 — Canais restantes

**Problema.** O Hermes tem 26 plataformas; o Donkey, 19. Faltam quatro
relevantes para equipes pequenas.

**Histórias, da mais simples à mais trabalhosa**
- **E13.1 ntfy.** Publicar notificações num tópico (agendamentos, alertas,
  respostas longas) e, opcionalmente, ouvir um tópico de entrada. HTTP
  simples, servidor próprio ou ntfy.sh.
- **E13.2 SimpleX.** Pelo `simplex-chat` em modo servidor (API WebSocket
  local). Sem identificador global de usuário: o pareamento é pelo contato.
- **E13.3 BlueBubbles (iMessage).** API REST e webhooks de um servidor
  BlueBubbles num Mac do operador.
- **E13.4 A2A.** O protocolo Agent2Agent: o Donkey publica um agent card e
  recebe tarefas de outros agentes por JSON-RPC; o agente remoto vira uma
  identidade como qualquer canal, com pareamento.

*Aceite geral:* cada canal com servidor falso nos testes, documentação em
`docs/topics/channels.md` e estado de conexão no status.

*Decisões (26/11):* A2A entra nesta rodada, e o Donkey também chama agentes
A2A (uma ferramenta de delegação, com lista de agentes permitidos e
aprovação, como as outras ações para fora).

---

## Ordem e dependências

E1 → E2 → E3 (E3.6 depois de E2) → E4 → E5 → E6 (E6.5 depois de E5).
E4 e E5 não dependem de E3 e podem andar em paralelo a ela se for útil.

Quarta rodada: E8 (feito) → E9 → E10 → E11 → E12 → E13. Renumerada em
26/11: a escrita no GitHub subiu para E11 e a supervisão para E12; os canais
restantes foram para o fim. E10.4 e os cartões de E9.2 e E9.4 usam o mesmo
mecanismo de aprovação que E11.3.
