# Roadmap do Donkey

> Documento único de planejamento. Substitui `tasks/` (removido em 25/11/2026,
> histórico no git) e os PRDs encerrados. O detalhamento executável está em
> [`docs/prd/PRD-roadmap.md`](prd/PRD-roadmap.md), um épico por frente.
> Decisões abaixo tomadas pelo mantenedor em 25/11/2026.

## 1. Onde estamos (27/11/2026, `master` em `b659f41e`)

- **Código:** 423 módulos e ~90 mil linhas em `src/`, 443 arquivos de teste,
  suíte completa verde. Arquitetura hexagonal com as fronteiras verificadas
  por testes de arquitetura.
- **Cobertura estimada:** ~83% (faixa 80–86%), contra ~91,9% do Hermes e
  ~73,8% do Pincer; quadro por domínio em
  `COMPARATIVO_DONKEY_PINCER_HERMES.md` (26/11), que sucede a série
  `COBERTURA_HERMES_VS_DONKEY_V*`: ~82,4% depois da segunda rodada, mais o
  auto-aprimoramento (E7), que soma memória de procedimento às ferramentas e
  à memória.
- **Canais (22):** Telegram, Discord, Slack, WhatsApp (Cloud API), Microsoft
  Teams, Google Chat, Mattermost, WeCom, WeChat, QQ (OneBot e oficial),
  Feishu, DingTalk, LINE, Matrix, Signal, IRC, SMS (Twilio), Email, ntfy,
  SimpleX, iMessage (BlueBubbles), CLI;
  multi-bot em Telegram, Discord, WhatsApp e Teams.
  Webhooks num receptor compartilhado; gateways de conexão permanente numa
  infraestrutura comum.
- **Providers:** OpenRouter, Anthropic, OpenAI, DeepSeek, Gemini, MiniMax, ZAI,
  Groq, Ollama, OpenCode Go e Zen, NVIDIA, Alibaba, Fireworks, Mistral, Bedrock
  e Azure OpenAI. Streaming pela rota escolhida, com tool calls.
- **Memória:** MAGMA em SQLite (busca híbrida semântica e lexical, grafo
  temporal), busca em conversas antigas, Backtrail (roteador de perguntas sobre
  o passado), datas relativas. Os `.md` do paddock são a vista legível.
- **Execução:** chamadas bloqueantes e streams fora do laço, em pools separados.
- **Observabilidade:** métricas Prometheus, traços por turno exportáveis em
  arquivo e por OpenTelemetry (OTLP/HTTP).
- **Entregas:** respostas que um canal recusa vão para uma fila de mensagens
  mortas e são reenviadas (1, 5 e 30 minutos); `donkey ctl deliveries`.
- **Auto-aprimoramento:** o agente escreve skills (`SKILL.md`) por pessoa,
  guardadas por uma guarda que bloqueia antes de gravar; uma revisão em
  segundo plano guarda o que merece, um curador consolida e arquiva, e
  `/learn`, `/refine`, `ctl skill learned` e `ctl insights` completam o ciclo.
- **Mídia nos canais (E9):** anexos entram em quase todos os canais; a
  ferramenta `send_file` sobe arquivo do paddock no Telegram, Mattermost,
  Teams, Discord, Slack e WhatsApp; o Teams é completo (imagens, cartão de
  consentimento, token de certificado, cartões com botões). O transporte HTTP
  lê no máximo 64 MiB de uma resposta (25 MB nos canais que baixam anexos).
- **Editores (E10):** `donkey acp` (Agent Client Protocol) no Zed e afins,
  pareado pela pessoa como um dispositivo (`/editor <código>`), com
  streaming, ferramentas, aprovações e leitura de arquivos do projeto.
- **Escrita no GitHub (E11):** abrir e fechar issues, comentar e rotular com
  o token de cada pessoa (`/github token`, só em conversa privada), sob uma
  política por repositório (`allow`, `ask`, `deny`; padrão `ask`).
- **Auditoria externa (26/11):** os cinco achados corrigidos (gravação
  exclusiva de anexos, `core` sem escrita em disco, heartbeat que não se
  repete, README fiel aos providers, provider estrito por agente).
- **Cache de prompt e contexto (E8):** o histórico só cresce (o contexto
  recuperado fica com a mensagem do turno; nada sai do começo), marcadores de
  cache para Claude, tokens do cache no uso, nos traços, nas métricas e no
  `/insights`; uma conversa longa é compactada em degrau (40% do contexto em
  modelos de 1M, 60% nos menores). Raciocínio adaptativo na Anthropic, com os
  blocos de raciocínio devolvidos intactos (Anthropic e Bedrock).

## 2. Primeira rodada: frentes decididas, todas feitas

| # | Frente | Decisão | Domínio (ganho estimado) | Épico |
|---:|---|---|---|---|
| 1 | Retomada de turno após queda | Retomar do início só se nenhuma ferramenta com efeito rodou; senão perguntar ao usuário. **Feito** (journal em `state/turns/`) | Durabilidade (~1 ponto) | E1 |
| 2 | Canal Microsoft Teams | Canal novo, antes do resto (há usuária em Teams). **Feito** (texto; anexos e cartões depois) | Canais (~0,5) | E2 |
| 3 | Multi-bot | Vários bots por canal numa instância; só a fachada (token, nome, persona, modelo); usuários, memória e sessões são os da instância. Telegram, Discord, WhatsApp e Teams. **Feito** (persona do operador em `{home}/agents/`; o bot que responde é o último com que a pessoa falou) | Multiagente (~1) | E3 |
| 4 | Kanban mínimo | Quadro de tarefas sem UI: ferramenta, comando e atribuição a agentes nomeados. **Feito** (`manage_tasks`, `/tasks`; tarefa de agente com prazo vira turno dele no dia) | Ferramentas (~1,5–2) | E4 |
| 5 | MCP sampling | Permitido com aprovação a cada pedido, e aprovação permanente por servidor como opção. **Feito** para servidores stdio; nenhuma chamada a MCP (stdio ou HTTP), a skill Deno ou a ferramenta nativa de rede (web, GitHub, git, transcrição, fala) segura mais o laço | Extensibilidade (~0,5) | E5 |
| 6 | Gestão pela TUI | Ampliar a TUI existente com ações de gestão; nada de UI web. **Feito**: usuários, pareamentos, agendamentos, aprovações (pendentes e permanentes), traços, agentes da instância (criar, editar e apagar num formulário) e saúde dos providers (chamadas, latência e cooldown da janela recente); o que ficou de fora está no §3 | Interfaces (~1,5) | E6 |

Ganho somado estimado: ~6 pontos, para ~84%. Medido depois (comparativo de
25/11): ~80,7%, pelos recortes do §3.

## 3. Itens abertos das frentes feitas

O que cada frente deixou de fora ao ser implementada. Nenhum está agendado.

| Item | Frente | Limite atual |
|---|---|---|
| Teams: edição de mensagens | E2 | arquivos entram e saem (com certificado, também nos apps de `[[bots]]`), cartões com botões; falta editar mensagens |
| MCP sampling por HTTP | E5 | só servidores stdio podem pedir sampling |
| Skill novo de usuário | E5 | as ferramentas aparecem a partir da mensagem seguinte (listagem em segundo plano) |
| IRC sem arquivos | 2ª rodada, frente 1 | o protocolo não carrega arquivos (só links, E9.5); só quem tem conta nos serviços da rede é atendido |
| Fila de mensagens mortas para ferramentas | 2ª rodada, frente 4 | só envios entram na fila: a falha de uma ferramenta volta ao modelo no mesmo turno, e um reenvio depois não teria quem recebesse o resultado |
| Resposta longa reenviada pela fila | 2ª rodada, frente 4 | uma resposta dividida que falhou no meio volta inteira, e os primeiros pedaços podem se repetir |
| Revisão de memória | E7.4 | a revisão cuida só de skills; os fatos ficam com o MAGMA, que já guarda cada turno relevante |
| Jornada como grafo | E7.7 | só em texto (`ctl` e TUI); o Hermes desenha um grafo no desktop |
| Custo nos insights | E7.8 | o Donkey não mantém tabela de preços; `/insights` (chat) e `ctl insights` mostram tokens |

Fechado em 27/11: o limite de tamanho no download. O transporte HTTP lê no
máximo 64 MiB de qualquer resposta (`DefaultMaxBodyBytes`) e para ali; os
canais que baixam anexos (Mattermost, SMS, Teams, Google Chat) leem no
máximo 25 MB, e um corpo maior é recusado sem nova tentativa.

Fechados em 26/11 (PR de itens abertos): promover uma skill para todas as
pessoas (`ctl skill promote`), `/insights` no chat (ferramenta `insights`), o
status dos canais sem socket contado (há quanto tempo chegou a última
mensagem) e, no Mattermost, os posts escritos com o socket caído (buscados ao
reconectar). Os que ficam: anexos no Teams, mídia nos canais novos e escrita
no GitHub são candidatas (§6) ou pedem decisão; sampling por HTTP exige o
transporte do MCP receber pedidos do servidor; a repetição de pedaços exige
que cada canal diga quais entregou; a skill Deno nova na mesma mensagem
esbarra na montagem síncrona da sessão; a revisão de memória e a jornada em
grafo são escolhas de desenho.

## 4. Segunda rodada (aprovada em 25/11)

Do comparativo de 25/11, em ordem de ganho estimado, seguidas dos itens
abertos do §3.

| Ordem | Frente | Ganho potencial | Referência | Estado |
|---:|---|---:|---|---|
| 1 | Canais: Mattermost, Google Chat, IRC, SMS | ~0,7 | Hermes `plugins/platforms` | **Feito** (#207 Mattermost, #208 SMS, #209 IRC, #210 Google Chat; só texto) |
| 2 | Ferramentas: GitHub e git nativos | ~0,5 | Pincer `tools/github`, `git_inspect` | **Feito** (#211; só leitura; I/O fora do laço) |
| 3 | Observabilidade: OpenTelemetry e replay de traço | ~0,5 | Pincer `trace_replay`, PromEx | **Feito** o OpenTelemetry (#212); replay recusado (§5) |
| 4 | Fila de mensagens mortas para envio e ferramenta | ~0,3 | Pincer `dead_letter_queue` | **Feito** para envios (#213); ferramentas no §3 |

Saíram da lista ao conferir o código: a API compatível com OpenAI já existe
(`/v1/chat/completions` com streaming e `/v1/models` no gateway); a guarda de
skills também (`saveSkillEntry` recusa permissões perigosas e a carga
revalida; a guarda do Pincer analisa o texto de um `SKILL.md`, e o skill do
Donkey é código num sandbox do Deno, onde essa análise vale pouco); OCR é
coberto por `inspect_image`, que usa um modelo com visão.

## 5. Terceira rodada: auto-aprimoramento (aprovada em 26/11)

Os sistemas de aprendizado do Hermes, todos (épico E7 no PRD). Decisões do
mantenedor: as skills aprendidas são **por pessoa** (nada aprendido com uma
pessoa chega a outra; o operador pode promover uma skill à mão); a revisão
em segundo plano usa um **modelo auxiliar barato** configurável (sem
configuração, a rota da sessão); toda skill nova ou alterada passa por uma
**guarda que bloqueia** exfiltração, injeção, caracteres invisíveis e
comandos destrutivos.

| História | Entrega | Estado |
|---|---|---|
| E7.1 Skills aprendidas | `SKILL.md` por pessoa no paddock, validação, guarda, proveniência, arquivar em vez de apagar | **Feito** (#220) |
| E7.2 `skill_manage` e `skill_view` | O agente cria, edita, corrige, arquiva e restaura; o índice entra no prompt a cada turno (sem cache de prompt, a nota de diferença do Hermes não é necessária) | **Feito** (#221) |
| E7.3 Uso | Contagem e último uso por skill | **Feito** (#222) |
| E7.4 Revisão em segundo plano | A cada 10 turnos ou 15 chamadas de ferramenta, uma cópia do agente com o modelo auxiliar guarda o que merece virar skill | **Feito** (#223) |
| E7.5 `/refine` e `/learn` | Revisão imediata; uma fonte vira skill, como turnos com prompt próprio | **Feito** (#224) |
| E7.6 Curador | No máximo a cada 7 dias: backup, arquiva o que não é usado há 90 dias (nunca o que a pessoa escreveu), funde quase duplicatas; `ctl skill rollback` | **Feito** (#225) |
| E7.7 Jornada | `ctl skill learned` e o detalhe da pessoa na TUI | **Feito** (#226) |
| E7.8 Insights | `donkey ctl insights`: turnos, tokens, ferramentas e falhas, providers, skills mais carregadas | **Feito** (#227); correções das revisões em #228 |

## 6. Quarta rodada (decisões tomadas em 26/11)

As seis candidatas do comparativo, épicos E8 a E13 no PRD, renumeradas em
26/11 (a escrita no GitHub subiu para E11, a supervisão para E12, os canais
restantes foram para o fim). E8 está feito; de E9 a E12 as decisões estão
tomadas; no E13, o A2A entra, e o Donkey também chama agentes A2A.

| Épico | Frente | O que entrega | Decisões pendentes |
|---|---|---|---|
| E8 | Cache de prompt | **Feito** (#232–#236; #237 e #238 completam: raciocínio devolvido intacto e histórico só de acréscimo): prefixo estável (o que muda a cada turno vai com a mensagem da pessoa), marcadores `cache_control` para Claude (Anthropic, Bedrock, OpenRouter), tokens do cache no uso, nos traços, nas métricas e no `/insights`, aviso de cache que nunca acerta, compactação de verdade (40% do contexto em modelos de 1M, 60% nos menores; `/compact` funciona) | Decididas em 26/11 |
| E9 | Mídia nos canais novos | **Feito** (#242, #243, #247–#249, #251–#253 e o PR de uploads): anexos entram em quase todos os canais; `send_file` sobe arquivo do paddock no Telegram, Mattermost, Teams, Discord, Slack e WhatsApp; o Teams completo (imagens, cartão de consentimento, token de certificado, cartões com botões) | Decididas em 26/11 |
| E10 | Interface para editores (ACP) | **Feito** (#256, #258, #260 e o PR de leitura): `donkey acp` no Zed e afins, pareado pela pessoa, com streaming, ferramentas, aprovações no editor e leitura de arquivos do projeto | Decididas: pareamento; memória compartilhada com os outros canais |
| E11 | Escrita no GitHub | **Feito** (#262 e o PR de escrita): abrir e fechar issues, comentar, rotular, com o token de cada pessoa (`/github token`, só em conversa privada) e política por repositório (`allow`, `ask`, `deny`; padrão `ask`) | Decididas: política por repositório; token da pessoa |
| E12 | Supervisão de adapters | **Feito:** E12.1 (auditoria e trava de padrões perigosos) e E12.2 (supervisor nas threads de canal e nos drenos, com `restarting` e `down` no status) feitos; E12.3, IRC, Mattermost e Discord como processo filho (`DONKEY_CHANNEL_PROCESSES`), que isola um `Defect` | Decidida: inspirar-se no OTP |
| E13 | Canais restantes | **Feito:** ntfy (#264), SimpleX (#265) e BlueBubbles/iMessage (#266) feitos; A2A feito: o servidor (v1.0, pareado como um editor) e o cliente (`delegate_to_agent`, com lista de agentes e aprovação) | Decididas: A2A entra, também como cliente |

## 7. Decidido não fazer

| Item | Motivo |
|---|---|
| Plugins carregados no processo | MCP (local e remoto, com OAuth) e skills Deno em sandbox são o sistema de extensão: nada de código de terceiro no processo. |
| Geração de imagem | Fora do escopo do assistente (decisão do §10, mantida). |
| OAuth de provider (assinaturas em vez de chave) | Recusado em 18/11, mantido. |
| Dashboard web | O projeto não tem UI web; a gestão vai para a TUI (E6). |
| Replay de traço | O traço não guarda conteúdo, por decisão de privacidade ("nunca o que foi dito"); reproduzir um turno exigiria guardar mensagens e saídas de ferramentas. A frente 3 da segunda rodada ficou na exportação OpenTelemetry. |
| Bots isolados (usuários e memória por bot) | Multi-bot é só fachada (E3); isolamento total seria uma instância por cliente. |

## 8. Pendências fora do código

- Revogar a chave da OpenRouter que foi colada numa conversa (criar outra) e
  conferir no painel o uso desde então.
- Ativar o Backtrail: `donkey ctl secret set PERPLEXITY_API_KEY` e reiniciar;
  confirmar por escrito o termo de não-treinamento da Perplexity.
- Testar o streaming do Bedrock com credenciais reais da AWS.
- Confirmar na documentação da Meta se um BSUID (`BR.…`) pode ser destinatário
  de resposta (WA-009).

## 9. Como cada frente é executada

As regras de sempre: TDD com vermelho visível; suíte completa, build e
checagem de fronteiras verdes antes do primeiro push de cada PR; nas
correções da revisão, só os testes dos arquivos tocados e o build (o CI roda
a suíte inteira a cada push); um PR por história, merge só com CI verde e
revisão respondida, nenhuma linha de atribuição. Todo comando em segundo
plano tem limite de tempo (`timeout`), e um hook do Claude Code avisa, ao
fim de cada resposta, quais ainda rodam. O que não chega ao
daemon não conta.
