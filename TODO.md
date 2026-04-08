# TODO

Backlog centralizado de trabalho pendente no Donkey.

## Multigraph Memory

Plano executável no ralph-tui: `tasks/prd.json`

- [ ] Tornar o Multigraph Memory a fonte única de verdade da memória.
  Hoje o runtime ainda opera em modo híbrido entre Markdown e grafo; o objetivo é inverter isso e tratar o grafo como backend autoritativo.

- [ ] Rebaixar Markdown para papel de export, visualização e debug.
  No runtime com `DONKEY_PG_DSN`, `USER.md`, `MEMORY.md` e `PREFERENCES.md` já não são mais a fonte de verdade; devem continuar úteis para bootstrap, inspeção humana, export e debug.

- [ ] Migrar `/memory`, `/status` e `/doctor` para consultar o Multigraph Memory.
  Esses comandos ainda refletem sobretudo arquivos e estado textual; precisam passar a mostrar a visão real do grafo e seus contadores.

- [ ] Aproximar a implementação do paper do Multigraph Memory.
  Prioridades: causalidade materializada de verdade, retrieval menos heurístico e política de recuperação mais próxima do desenho do paper.

- [ ] Consolidar MAGMA SQLite self-contained com SQLite base e `sqlite-vec` embutidos.
  Prioridades: manter o caminho local-first como padrão, reduzir ao mínimo os artefatos externos opcionais e deixar o trilho `GraphQLite` preparado como fase seguinte.

- [ ] Adicionar camada self-improving e contemplative sobre o Multigraph Memory.
  Prioridades: commitments/promises, heartbeat de accountability, episode journaling, SIS de lessons e Knowledge Library separada da memória autobiográfica.

## Telegram e Bootstrap

Backlog ativo para o ralph loop: `tasks/prd.json` (`US-022` a `US-025`)

- [ ] Fechar gaps de ingress de session-task no Telegram.
  Prioridade: garantir que texto e callbacks relevantes sempre sobem ou reutilizam o orchestrator antes de enfileirar tasks como `/reset`.

- [ ] Manter o `/reset` estritamente dentro do onboarding.
  Prioridade: depois do reset, o bot deve ficar em bootstrap até o usuário retomar o fluxo, sem rebuild/runtime drift nem completion indevida.

- [ ] Corrigir o picker de modelos da Z.ai.
  Prioridade: escolher `zai-coding` deve mostrar o catálogo certo com botões; se um provider não tiver modelos, a UI deve dizer isso explicitamente.

- [ ] Resolver slash commands órfãos ainda marcados como session-task.
  Prioridade: `/verbose`, `/exec`, `/queue`, `/usage` e `/tts` não devem cair no fallback conversacional por falta de handler explícito.
