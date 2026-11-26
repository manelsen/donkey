# Roadmap do Donkey

> Documento único de planejamento. Substitui `tasks/` (removido em 25/11/2026,
> histórico no git) e os PRDs encerrados. O detalhamento executável está em
> [`docs/prd/PRD-roadmap.md`](prd/PRD-roadmap.md), um épico por frente.
> Decisões abaixo tomadas pelo mantenedor em 25/11/2026.

## 1. Onde estamos (26/11/2026, `master` em `d3e20826`)

- **Código:** 398 módulos e ~85 mil linhas em `src/`, 409 arquivos de teste,
  suíte completa verde. Arquitetura hexagonal com as fronteiras verificadas
  por testes de arquitetura.
- **Cobertura estimada:** ~83% (faixa 80–86%), contra ~91,9% do Hermes e
  ~73,8% do Pincer; quadro por domínio em
  `COMPARATIVO_DONKEY_PINCER_HERMES.md` (26/11), que sucede a série
  `COBERTURA_HERMES_VS_DONKEY_V*`: ~82,4% depois da segunda rodada, mais o
  auto-aprimoramento (E7), que soma memória de procedimento às ferramentas e
  à memória.
- **Canais (19):** Telegram, Discord, Slack, WhatsApp (Cloud API), Microsoft
  Teams, Google Chat, Mattermost, WeCom, WeChat, QQ (OneBot e oficial),
  Feishu, DingTalk, LINE, Matrix, Signal, IRC, SMS (Twilio), Email, CLI;
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
| Teams com anexos e cartões | E2 | só texto entra e sai |
| MCP sampling por HTTP | E5 | só servidores stdio podem pedir sampling |
| Estado de conexão dos canais por webhook e long poll | E6 | Discord, Mattermost, IRC e Slack e QQ em modo socket mostram se estão conectados (`connected`, `reconnecting c/r`, `stopped`); os demais aparecem como `active`, sem saber da conexão |
| Skill novo de usuário | E5 | as ferramentas aparecem a partir da mensagem seguinte (listagem em segundo plano) |
| Escrita no GitHub (abrir issue, comentar) | 2ª rodada, frente 2 | fora de propósito: o agente lê texto de terceiros; pede decisão sobre aprovação |
| Mattermost, SMS, IRC e Google Chat com mídia | 2ª rodada, frente 1 | só texto; no IRC, só quem tem conta nos serviços da rede é atendido |
| Mensagens do Mattermost com o socket caído | 2ª rodada, frente 1 | não são reapresentadas ao reconectar |
| Fila de mensagens mortas para ferramentas | 2ª rodada, frente 4 | só envios entram na fila: a falha de uma ferramenta volta ao modelo no mesmo turno, e um reenvio depois não teria quem recebesse o resultado |
| Resposta longa reenviada pela fila | 2ª rodada, frente 4 | uma resposta dividida que falhou no meio volta inteira, e os primeiros pedaços podem se repetir |
| Promover uma skill para todas as pessoas | E7 | estava na decisão (o operador promove à mão) e não foi feito: as skills são só por pessoa |
| Revisão de memória | E7.4 | a revisão cuida só de skills; os fatos ficam com o MAGMA, que já guarda cada turno relevante |
| `/insights` no chat e custo | E7.8 | só `donkey ctl insights`, e sem custo estimado (o Donkey não mantém tabela de preços) |
| Jornada como grafo | E7.7 | só em texto (`ctl` e TUI); o Hermes desenha um grafo no desktop |

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

## 6. Candidatas para a próxima rodada

Nenhuma decidida. Do comparativo de 26/11 e do que as rodadas deixaram.

| Ordem | Frente | Por quê | Referência |
|---:|---|---|---|
| 1 | Cache de prompt | O Donkey não usa nenhum: paga o contexto inteiro a cada turno. Marcadores `cache_control` na Anthropic, leitura de tokens cacheados, compactação antes de expirar | Hermes `caching`, `compression` |
| 2 | Mídia nos canais novos e no Teams | Google Chat, Mattermost, SMS (MMS), IRC e Teams só com texto | Hermes `plugins/platforms` |
| 3 | Interface para editores (ACP) | A maior distância restante (Interfaces, 72% contra 97%) | Hermes `acp_adapter` |
| 4 | Canais restantes do Hermes | SimpleX, BlueBubbles, ntfy, A2A | Hermes `plugins/platforms` |
| 5 | Escrita no GitHub com aprovação | Pede decisão sobre aprovação | Pincer `tools/github` |
| 6 | Supervisão de adapters | Um `Defect` num adapter derruba o daemon | Pincer, árvore OTP |

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
