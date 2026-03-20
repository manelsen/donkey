# REFACTOR_PLAN — Prioridades de Refatoração

Lista priorizada de refactors para reduzir risco estrutural e melhorar a evolutividade do runtime.

## Status

Plano histórico. A refatoração-base descrita aqui já foi executada no runtime atual:
- daemon, orchestrator, bootstrap, outbound e native tools foram fatiados;
- contratos frágeis como `ask`, jobs, `workerOut`, drift de catálogo e persistência periódica foram corrigidos;
- o arquivo permanece como registro da direção adotada, não mais como backlog principal.

## Direção arquitetural

Princípios a perseguir em toda refatoração:

- desacoplamento máximo entre runtime, canais, providers, tools e persistência;
- separação explícita entre funções puras e funções efetivas;
- funções pequenas, com responsabilidade única e contratos estreitos;
- redução de estado implícito e de ordenação implícita;
- transformação de payloads e decisões em helpers puros;
- I/O, side effects e coordenação assíncrona concentrados em bordas finas.

Critérios práticos:

- preferir funções puras para parse, roteamento, decisão, montagem de prompt, normalização de payload e transições de estado;
- preferir funções efetivas curtas, idealmente só fazendo orquestração e chamando helpers puros;
- evitar módulos “Deus”, especialmente em `src/donkey.nim` e `src/donkey/app/orchestrator.nim`;
- todo fluxo complexo deve ter uma camada de decisão pura antes da camada de execução efetiva.

## P0

- Unificar a resolução de paddock.
  Hoje o orquestrador monta `~/.donkey/paddocks/<uid>` enquanto a memória usa `cfg.paddocks`. Isso cria risco real de escrever e ler estados diferentes. Centralizar em uma única função ou passar o paddock resolvido explicitamente ao orquestrador.

- Separar o `ToolLoop` de `src/donkey/app/orchestrator.nim`.
  Extrair a execução de tool calls, guard de repetição, progress embed e fallback MCP para um módulo dedicado. É o trecho mais acoplado e mais sujeito a regressão.

- Corrigir o contrato de jobs em `src/donkey/app/native_tools.nim`.
  Ou implementar jobs reais para `task`, `await` e `cancel_job`, ou remover essa superfície até existir runtime compatível. Hoje a API promete mais do que entrega.

- Isolar `ask` do inbox principal.
  O ideal é um mecanismo de correlação de resposta ou um subcanal de espera, porque `ctx.inbox.get()` compete com mensagens normais e callbacks.

## P1

- Extrair a camada de entrada por canal de `src/donkey.nim`.
  O loop do daemon está concentrando bootstrap, polling, comandos, reminders e outbox routing. A direção melhor é separar:
  `ChannelIngressRuntime`, `TelegramCommandRouter`, `DiscordInteractionRouter` e, quando fizer sentido, um `SharedCommandRouter`.

- Extrair o onboarding para um módulo próprio.
  A máquina de estados de personalidade e coleta de perfil já justifica um `OnboardingRuntime` ou `OnboardingStateMachine`.

- Fatiar `ensureSession` em partes puras e efetivas.
  Exemplos naturais:
  seleção de provider,
  composição da lista de tools,
  descoberta de skills do usuário,
  normalização do payload de entrada,
  spawn efetivo do orquestrador.

- Substituir `workerOut` compartilhado por resposta correlacionada por request id, ou separar filas de retorno de memória e tools.
  Hoje funciona por disciplina de uso, não por contrato robusto.

- Persistir sessão periodicamente, não só em `reset` e cancelamento.
  Um snapshot por turn ou por intervalo já reduz perda de histórico em crash.

## P2

- Formalizar um `SessionRuntime` que receba dependências já prontas.
  Provider, tools, paddock, `searchFn` e `typingFn` devem chegar resolvidos, reduzindo a complexidade de `ensureSession`.

- Extrair reducers puros de onboarding, tool loop e comandos.
  Em vez de espalhar `if` e `case` diretamente no fluxo efetivo, mover decisões para funções puras do tipo:
  `parseInboundCommand`,
  `advanceOnboarding`,
  `decideToolDispatch`,
  `buildOutboundOps`.

- Unificar tools legadas e tools nativas.
  `schedule_reminder` ainda tem tratamento especial no orquestrador; isso deveria virar caminho único.

- Revisar schemas e descriptions em `src/donkey/domain/more_tools.nim` e `src/donkey/domain/builtin_tools.nim`.
  Eles devem refletir o runtime real para não induzir o LLM a contratos inexistentes.

- Endurecer IPC e concorrência interprocesso.
  Se houver chance de múltiplos daemons no mesmo `DONKEY_HOME`, o runtime atual não coordena acesso.

## P3

- Criar testes de contrato de runtime.
  Cobrir sessão nova vs existente, streaming com edição incremental, `ask` seguido de callback ou mensagem concorrente, persistência de reminders e tools nativas com path fora do paddock.

- Reduzir acoplamento textual entre memória e prompt.
  `tkLoadCtx` devolve texto consolidado; um tipo estruturado intermediário deixaria a composição mais explícita.

- Separar “erro operacional” de “resultado textual de tool”.
  Hoje muita falha vira `"Error: ..."` indistinto, o que enfraquece contrato e observabilidade.

## Ordem sugerida de execução

1. Unificar paddock.
2. Corrigir contrato de jobs ou remover superfície falsa.
3. Isolar `ask`.
4. Extrair `ToolLoop`.
5. Extrair camada de entrada por canal e roteadores específicos.
6. Separar onboarding.
7. Trocar `workerOut` compartilhado por correlação explícita.
8. Fatiar `ensureSession` em helpers puros + borda efetiva.
9. Adicionar persistência periódica de sessão.
10. Revisar schemas das tools.
11. Expandir testes de contrato.

## Critério de sucesso

- cada módulo central passa a ter uma responsabilidade mais estreita;
- contratos aparentes e contratos reais ficam alinhados;
- estado de sessão e workspace deixam de divergir;
- o runtime reduz dependência de ordenação implícita;
- falhas de concorrência e perda de histórico ficam menos prováveis;
- decisões de negócio e roteamento passam a ser testáveis sem I/O;
- a maior parte da complexidade migra para funções puras, pequenas e componíveis.
