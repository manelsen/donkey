# Roadmap do Donkey

> Documento único de planejamento. Substitui `tasks/` (removido em 25/11/2026,
> histórico no git) e os PRDs encerrados. O detalhamento executável está em
> [`docs/prd/PRD-roadmap.md`](prd/PRD-roadmap.md), um épico por frente.
> Decisões abaixo tomadas pelo mantenedor em 25/11/2026.

## 1. Onde estamos (25/11/2026, `master` em `b645e3bb`)

- **Código:** 364 módulos e ~80 mil linhas em `src/`, 373 arquivos de teste,
  suíte completa verde (364 alvos). Arquitetura hexagonal com as fronteiras
  verificadas por testes de arquitetura.
- **Cobertura estimada:** ~80,7% (faixa 78–83%), contra ~91,7% do Hermes e
  ~73,8% do Pincer; quadro por domínio em
  `COMPARATIVO_DONKEY_PINCER_HERMES.md` (25/11), que sucede a série
  `COBERTURA_HERMES_VS_DONKEY_V*`. Fica abaixo dos ~84% projetados para
  E1–E6 porque as frentes entraram com recortes (§3).
- **Canais (15):** Telegram, Discord, Slack, WhatsApp (Cloud API), Microsoft
  Teams, WeCom, WeChat, QQ (OneBot e oficial), Feishu, DingTalk, LINE, Matrix,
  Signal, Email, CLI; multi-bot em Telegram, Discord, WhatsApp e Teams.
  Webhooks num receptor compartilhado; gateways de conexão permanente numa
  infraestrutura comum.
- **Providers:** OpenRouter, Anthropic, OpenAI, DeepSeek, Gemini, MiniMax, ZAI,
  Groq, Ollama, OpenCode Go e Zen, NVIDIA, Alibaba, Fireworks, Mistral, Bedrock
  e Azure OpenAI. Streaming pela rota escolhida, com tool calls.
- **Memória:** MAGMA em SQLite (busca híbrida semântica e lexical, grafo
  temporal), busca em conversas antigas, Backtrail (roteador de perguntas sobre
  o passado), datas relativas. Os `.md` do paddock são a vista legível.
- **Execução:** chamadas bloqueantes e streams fora do laço, em pools separados.
- **Observabilidade:** métricas Prometheus e traços por turno exportáveis.

## 2. Primeira rodada: frentes decididas, todas feitas

| # | Frente | Decisão | Domínio (ganho estimado) | Épico |
|---:|---|---|---|---|
| 1 | Retomada de turno após queda | Retomar do início só se nenhuma ferramenta com efeito rodou; senão perguntar ao usuário. **Feito** (journal em `state/turns/`) | Durabilidade (~1 ponto) | E1 |
| 2 | Canal Microsoft Teams | Canal novo, antes do resto (há usuária em Teams). **Feito** (texto; anexos e cartões depois) | Canais (~0,5) | E2 |
| 3 | Multi-bot | Vários bots por canal numa instância; só a fachada (token, nome, persona, modelo); usuários, memória e sessões são os da instância. Telegram, Discord, WhatsApp e Teams. **Feito** (persona do operador em `{home}/agents/`; o bot que responde é o último com que a pessoa falou) | Multiagente (~1) | E3 |
| 4 | Kanban mínimo | Quadro de tarefas sem UI: ferramenta, comando e atribuição a agentes nomeados. **Feito** (`manage_tasks`, `/tasks`; tarefa de agente com prazo vira turno dele no dia) | Ferramentas (~1,5–2) | E4 |
| 5 | MCP sampling | Permitido com aprovação a cada pedido, e aprovação permanente por servidor como opção. **Feito** para servidores stdio; nenhuma chamada de ferramenta segura mais o laço (MCP stdio e HTTP e skills Deno são assíncronos) | Extensibilidade (~0,5) | E5 |
| 6 | Gestão pela TUI | Ampliar a TUI existente com ações de gestão; nada de UI web. **Feito**: usuários, pareamentos, agendamentos, aprovações (pendentes e permanentes), traços, agentes da instância (criar, editar e apagar num formulário) e saúde dos providers (chamadas, latência e cooldown da janela recente); o que ficou de fora está no §3 | Interfaces (~1,5) | E6 |

Ganho somado estimado: ~6 pontos, para ~84%. Medido depois (comparativo de
25/11): ~80,7%, pelos recortes do §3.

## 3. Itens abertos das frentes feitas

O que cada frente deixou de fora ao ser implementada. Nenhum está agendado.

| Item | Frente | Limite atual |
|---|---|---|
| Teams com anexos e cartões | E2 | só texto entra e sai |
| MCP sampling por HTTP | E5 | só servidores stdio podem pedir sampling |
| Estado de conexão dos canais | E6 | o status do daemon não o informa; a TUI mostra só os canais ativos |
| Saúde de todos os providers | E6 | o status manda métricas só dos 5 mais usados; os outros aparecem como "no recent calls" |
| Skill novo de usuário | E5 | as ferramentas aparecem a partir da mensagem seguinte (listagem em segundo plano) |
| Renovação de token OAuth do MCP por HTTP | E5 | ainda roda no laço (rara, com prazo próprio) |

## 4. Segunda rodada (aprovada em 25/11)

Do comparativo de 25/11, em ordem de ganho estimado, seguidas dos itens
abertos do §3.

| Ordem | Frente | Ganho potencial | Referência |
|---:|---|---:|---|
| 1 | Canais: Mattermost, Google Chat, IRC, SMS | ~0,7 | Hermes `plugins/platforms` |
| 2 | Ferramentas: GitHub e git nativos | ~0,5 | Pincer `tools/github`, `git_inspect` |
| 3 | Observabilidade: OpenTelemetry e replay de traço | ~0,5 | Pincer `trace_replay`, PromEx |
| 4 | Fila de mensagens mortas para envio e ferramenta | ~0,3 | Pincer `dead_letter_queue` |

Saíram da lista ao conferir o código: a API compatível com OpenAI já existe
(`/v1/chat/completions` com streaming e `/v1/models` no gateway); a guarda de
skills também (`saveSkillEntry` recusa permissões perigosas e a carga
revalida; a guarda do Pincer analisa o texto de um `SKILL.md`, e o skill do
Donkey é código num sandbox do Deno, onde essa análise vale pouco); OCR é
coberto por `inspect_image`, que usa um modelo com visão.

## 5. Decidido não fazer

| Item | Motivo |
|---|---|
| Plugins carregados no processo | MCP (local e remoto, com OAuth) e skills Deno em sandbox são o sistema de extensão: nada de código de terceiro no processo. |
| Geração de imagem | Fora do escopo do assistente (decisão do §10, mantida). |
| OAuth de provider (assinaturas em vez de chave) | Recusado em 18/11, mantido. |
| Dashboard web | O projeto não tem UI web; a gestão vai para a TUI (E6). |
| Bots isolados (usuários e memória por bot) | Multi-bot é só fachada (E3); isolamento total seria uma instância por cliente. |

## 6. Pendências fora do código

- Revogar a chave da OpenRouter que foi colada numa conversa (criar outra) e
  conferir no painel o uso desde então.
- Ativar o Backtrail: `donkey ctl secret set PERPLEXITY_API_KEY` e reiniciar;
  confirmar por escrito o termo de não-treinamento da Perplexity.
- Testar o streaming do Bedrock com credenciais reais da AWS.
- Confirmar na documentação da Meta se um BSUID (`BR.…`) pode ser destinatário
  de resposta (WA-009).

## 7. Como cada frente é executada

As regras de sempre: TDD com vermelho visível; suíte completa, build e
checagem de fronteiras verdes antes do primeiro push de cada PR; nas
correções da revisão, só os testes dos arquivos tocados e o build (o CI roda
a suíte inteira a cada push); um PR por história, merge só com CI verde e
revisão respondida, nenhuma linha de atribuição. O que não chega ao
daemon não conta.
