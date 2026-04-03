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

- [ ] Adicionar camada self-improving e contemplative sobre o Multigraph Memory.
  Prioridades: commitments/promises, heartbeat de accountability, episode journaling, SIS de lessons e Knowledge Library separada da memória autobiográfica.
