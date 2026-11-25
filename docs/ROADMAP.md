# Roadmap do Donkey

> Documento único de planejamento. Substitui `tasks/` (removido em 25/11/2026,
> histórico no git) e os PRDs encerrados. O detalhamento executável está em
> [`docs/prd/PRD-roadmap.md`](prd/PRD-roadmap.md), um épico por frente.
> Decisões abaixo tomadas pelo mantenedor em 25/11/2026.

## 1. Onde estamos (25/11/2026, `master` em `e9c67e4d`)

- **Código:** 342 módulos e ~77 mil linhas em `src/`, 349 arquivos de teste,
  suíte completa verde. Arquitetura hexagonal com as fronteiras verificadas por
  testes de arquitetura.
- **Cobertura estimada frente ao Hermes:** ~78,3% (Hermes ~91,7%); detalhe por
  domínio na seção 12 de `COBERTURA_HERMES_VS_DONKEY_V5.md`.
- **Canais (14):** Telegram, Discord, Slack, WhatsApp (Cloud API), WeCom,
  WeChat, QQ (OneBot e oficial), Feishu, DingTalk, LINE, Matrix, Signal, Email,
  CLI. Webhooks num receptor compartilhado; gateways de conexão permanente numa
  infraestrutura comum.
- **Providers:** OpenRouter, Anthropic, OpenAI, DeepSeek, Gemini, MiniMax, ZAI,
  Groq, Ollama, OpenCode Go e Zen, NVIDIA, Alibaba, Fireworks, Mistral, Bedrock
  e Azure OpenAI. Streaming pela rota escolhida, com tool calls.
- **Memória:** MAGMA em SQLite (busca híbrida semântica e lexical, grafo
  temporal), busca em conversas antigas, Backtrail (roteador de perguntas sobre
  o passado), datas relativas. Os `.md` do paddock são a vista legível.
- **Execução:** chamadas bloqueantes e streams fora do laço, em pools separados.
- **Observabilidade:** métricas Prometheus e traços por turno exportáveis.

## 2. Frentes decididas, em ordem

| # | Frente | Decisão | Domínio (ganho estimado) | Épico |
|---:|---|---|---|---|
| 1 | Retomada de turno após queda | Retomar do início só se nenhuma ferramenta com efeito rodou; senão perguntar ao usuário. **Feito** (journal em `state/turns/`) | Durabilidade (~1 ponto) | E1 |
| 2 | Canal Microsoft Teams | Canal novo, antes do resto (há usuária em Teams). **Feito** (texto; anexos e cartões depois) | Canais (~0,5) | E2 |
| 3 | Multi-bot | Vários bots por canal numa instância; só a fachada (token, nome, persona, modelo); usuários, memória e sessões são os da instância. Telegram, Discord, WhatsApp e Teams. **Feito** (persona do operador em `{home}/agents/`; o bot que responde é o último com que a pessoa falou) | Multiagente (~1) | E3 |
| 4 | Kanban mínimo | Quadro de tarefas sem UI: ferramenta, comando e atribuição a agentes nomeados. **Feito** (`manage_tasks`, `/tasks`; tarefa de agente com prazo vira turno dele no dia) | Ferramentas (~1,5–2) | E4 |
| 5 | MCP sampling | Permitido com aprovação a cada pedido, e aprovação permanente por servidor como opção. **Feito** para servidores stdio (o cliente MCP agora é assíncrono); HTTP e skills Deno ainda síncronos | Extensibilidade (~0,5) | E5 |
| 6 | Gestão pela TUI | Ampliar a TUI existente com ações de gestão; nada de UI web | Interfaces (~1,5) | E6 |

Ganho somado estimado: ~6 pontos, para ~84%.

## 3. Decidido não fazer

| Item | Motivo |
|---|---|
| Plugins carregados no processo | MCP (local e remoto, com OAuth) e skills Deno em sandbox são o sistema de extensão: nada de código de terceiro no processo. |
| Geração de imagem | Fora do escopo do assistente (decisão do §10, mantida). |
| OAuth de provider (assinaturas em vez de chave) | Recusado em 18/11, mantido. |
| Dashboard web | O projeto não tem UI web; a gestão vai para a TUI (E6). |
| Bots isolados (usuários e memória por bot) | Multi-bot é só fachada (E3); isolamento total seria uma instância por cliente. |

## 4. Pendências fora do código

- Revogar a chave da OpenRouter que foi colada numa conversa (criar outra) e
  conferir no painel o uso desde então.
- Ativar o Backtrail: `donkey ctl secret set PERPLEXITY_API_KEY` e reiniciar;
  confirmar por escrito o termo de não-treinamento da Perplexity.
- Testar o streaming do Bedrock com credenciais reais da AWS.
- Confirmar na documentação da Meta se um BSUID (`BR.…`) pode ser destinatário
  de resposta (WA-009).

## 5. Como cada frente é executada

As regras de sempre: TDD com vermelho visível, suíte completa, build e checagem
de fronteiras verdes antes de cada push, um PR por história, merge só com CI
verde e revisão respondida, nenhuma linha de atribuição. O que não chega ao
daemon não conta.
