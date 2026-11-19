[PRD]
# PRD: Compilar a suíte de testes do Donkey por grupos

## Overview

`scripts/run_tests.sh` compila um executável para cada arquivo de teste. A suíte
completa repete a compilação das mesmas dependências centenas de vezes. A mudança
é compilar um executável por grupo de arquivos e iniciar um subprocesso desse
executável para cada arquivo solicitado.

Em um piloto com Nim 2.2.12 e ORC, 12 arquivos de `tests/core` passaram de 29,36 s
para 9,78 s a frio e de 14,38 s para 3,47 s a quente. Os 227 resultados
coincidiram arquivo por arquivo. Uma segunda prova preservou os 14 casos de
`t_provider_executor.nim`, incluindo a regressão de ORC. Os números são de
amostras locais.

## Goals

- Concluir a suíte padrão completa em até um terço do tempo do runner
  legado, com cache frio e quente, em uma comparação controlada.
- Preservar os casos, asserções, fixtures, skips e o isolamento de processo de
  cada arquivo.
- Manter `nimble test` e a execução por arquivo ou diretório. Compilar cada grupo
  selecionado uma vez por invocação, inclusive quando o CI usa shards.

## Quality Gates

Estes comandos devem passar ao final de cada história:

- `git diff --check`
- `bash -n scripts/run_tests.sh`
- `bash scripts/check_boundaries.sh`

Além disso, rode a verificação indicada na história com Nim 2.2.12 e as
dependências do checkout. Compare os tempos da suíte completa em US-009.
Guarde os logs fora do repositório.

## Execution Plan

1. Execute uma história de cada vez, na ordem abaixo. Em US-007, faça um lote por
   vez e compare os resultados antes de pegar o próximo.
2. Antes de editar cada lote, rode os arquivos no modo legado e guarde o
   relatório de referência. Depois da edição, compare ambos os modos com
   esse relatório. Registre o comando, o código de saída, o total de arquivos
   e casos e, quando houver medição, o tempo de parede.
3. Se um caso sumir, mudar de status ou rodar duas vezes, identifique o arquivo
   e corrija a divergência antes de avançar. Se faltar um pré-requisito de um
   perfil opt-in, registre o perfil e o motivo.

## User Stories

### US-001: Registrar a execução atual por arquivo

**Description:** Como mantenedor, quero comparar os mesmos casos antes e depois
da migração.

**Acceptance Criteria:**

- [ ] Com `TEST_REPORT_DIR` apontando para um diretório vazio por execução,
  o runner salva um índice TSV com caminho, status e motivo de skip, além
  do log de cada arquivo executado. Com a variável ausente, a saída normal
  continua disponível.
- [ ] Cada arquivo descoberto aparece como executado, falho ou pulado. Um skip
  de arquivo inclui o motivo, como stress desabilitado, perfil separado ou
  ferramenta ausente. Skips de casos continuam nos logs.
- [ ] A comparação considera o caminho do arquivo, a suíte, o nome e o status
  de cada caso, preservando repetições legítimas. Compare os logs de
  `tests/core/t_pipeops.nim` e `tests/core/t_cron.nim` em duas execuções.
  Eles cobrem `std/unittest` e `unittest2`, respectivamente.
- [ ] `python3 scripts/compare_test_reports.py ANTES DEPOIS` retorna `0`
  quando os relatórios coincidem e retorna falha com os caminhos e casos
  divergentes quando há diferença.
- [ ] O arquivo vazio `tests/adapters/memory/t_hybrid_search.nim` aparece no
  inventário como exceção conhecida com zero casos. O comparador acusa qualquer
  arquivo executado que passe a produzir zero casos.

### US-002: Rodar o primeiro grupo com subprocessos

**Description:** Como desenvolvedor, quero compilar testes relacionados juntos
e continuar rodando cada arquivo isoladamente.

**Acceptance Criteria:**

- [ ] `TEST_RUNNER=grouped` usa um manifesto simples com uma linha por arquivo
  agrupado, no formato `grupo<TAB>caminho`. `TEST_RUNNER=legacy` roda cada
  arquivo com a compilação individual. O legado é o padrão até US-009.
- [ ] O grupo inicial contém estes arquivos de `tests/core`:
  `t_actor`, `t_approval_pure`, `t_command_catalog`, `t_command_routing`,
  `t_diagnostics`, `t_output_sanitizer`, `t_pipeops`, `t_provider_catalog`,
  `t_provider_failover`, `t_routing_policy`, `t_structured_tool_result`
  e `t_utf8_clip`.
- [ ] Cada módulo exporta `runTests*()` e o chama em `when isMainModule`.
  Importar os módulos prepara declarações. Fixtures e corpos de testes rodam
  na chamada de `runTests()`.
- [ ] O runner gera imports com aliases e despacha por caminho completo relativo
  ao repositório. Passe esse caminho ao subprocesso via variável de ambiente e
  limpe-a antes de chamar o módulo. Cada subprocesso roda somente um módulo.
- [ ] Compare os dois modos em `bash scripts/run_tests.sh tests/core`. Confirme
  uma compilação compartilhada para os 12 arquivos, execução direta de
  `t_pipeops.nim` e falha do runner ao introduzir temporariamente uma asserção
  falsa. Remova a alteração temporária ao terminar a verificação.

### US-003: Preservar seleção, cache e diagnóstico

**Description:** Como desenvolvedor, quero selecionar testes com precisão
e receber o caminho e o log quando um teste falhar.

**Acceptance Criteria:**

- [ ] Selecionar só `tests/core/t_pipeops.nim` em modo agrupado roda apenas
  esse arquivo. Selecionar `tests/core` junto com o mesmo arquivo o roda uma
  vez. Arquivos fora do manifesto continuam elegíveis pelo caminho individual.
- [ ] Um alvo inexistente ou um diretório sem testes retorna código `2`.
  Um erro no agendamento de workers retorna falha mesmo sem um log de teste.
- [ ] Um manifesto com caminho duplicado ou inexistente, um grupo que falha
  ao compilar ou um subprocesso com saída diferente de zero tornam o
  comando inteiro falho. O diagnóstico identifica o grupo ou arquivo e
  mostra o log correspondente.
- [ ] Entrypoints gerados e objetos de compilação ficam no cache. Repetir a
  execução reutiliza o cache do grupo. Mudar um teste ou uma dependência
  recompila o necessário. Dois runners simultâneos para o mesmo grupo produzem
  relatórios completos, com compilação protegida contra escrita concorrente.

### US-004: Completar a migração de core

**Description:** Como mantenedor, quero aplicar o modelo ao restante de core
com a mesma cobertura do runner individual.

**Acceptance Criteria:**

- [ ] Migre os arquivos elegíveis restantes de `tests/core`. Compare
  `tests/core` nos dois modos, inclusive `t_cron.nim`.
- [ ] Preserve os frameworks atuais e registre o caminho e o motivo de cada
  exceção que continuar individual.

### US-005: Migrar os testes de providers

**Description:** Como mantenedor, quero compartilhar as dependências de
providers e conservar a regressão de ORC.

**Acceptance Criteria:**

- [ ] Migre providers em `tests/domain/providers`, `tests/adapters/provider`,
  `tests/provider` e `tests/app/t_provider_executor.nim`. Compare os
  resultados e confira o caso de passagem de dados gerenciados pelo GC entre
  threads no executor.
- [ ] Registre o caminho e o motivo de cada exceção que continuar individual.

### US-006: Migrar os testes de canais

**Description:** Como mantenedor, quero compartilhar as dependências dos canais
e manter o isolamento dos seus testes de integração.

**Acceptance Criteria:**

- [ ] Migre canais em `tests/domain/channels`, `tests/adapters/channel` e
  `tests/channel`. Compare a seleção completa e uma seleção de arquivo.
- [ ] Registre o caminho e o motivo de cada exceção que continuar individual.

### US-007: Migrar os demais testes da suíte padrão

**Description:** Como mantenedor, quero compartilhar a compilação nos demais
diretórios sem mudar o ambiente esperado pelos testes.

**Acceptance Criteria:**

- [ ] Migre primeiro `tests/config`, `tests/tool`, `tests/domain/tools` e
  `tests/adapters/tools`. Depois, migre os demais arquivos padrão por
  diretório, incluindo os restantes de `tests/app`, `tests/domain` e
  `tests/adapters`. Comece com grupos de até
  25 arquivos e mantenha dependências semelhantes juntas. Compare cada lote
  nos dois modos antes de iniciar o próximo.
- [ ] Todo arquivo padrão está em um grupo ou segue pelo caminho individual
  com motivo registrado. Mantenha
  `tests/app/t_ingestion_regression.nim` individual, pois usa
  `getAppDir()/downloads`. Use o mesmo critério para dependência da localização
  do executável, inicialização que só pode ocorrer em um binário dedicado ou
  perfil de compilação incompatível.
- [ ] Os comandos e decisões de execução para stress, SQLite opt-in, PostgreSQL,
  AGE e WASM estão de acordo com o runner e o README atuais.

### US-008: Encaixar os grupos nos shards do CI

**Description:** Como mantenedor, quero que o CI compile cada grupo em um só
shard e continue aceitando os alvos da seleção por impacto.

**Acceptance Criteria:**

- [ ] A atribuição estável aos shards usa o inventário completo do checkout.
  Filtrar por caminho depois da atribuição mantém o mesmo grupo no mesmo
  shard. Arquivos individuais são unidades independentes.
- [ ] Em modo agrupado, a união dos quatro shards coincide com a execução
  sem shard e nenhum arquivo elegível aparece em dois shards. Compare também
  com uma seleção de diretório mais um arquivo. Um shard vazio termina
  com sucesso.
- [ ] O workflow continua com quatro jobs de testes, seleção por impacto
  em PRs e suíte completa em `master`. A publicação segue dependendo dos
  testes. `scripts/affected_tests.sh` continua emitindo os mesmos alvos.

### US-009: Medir a suíte completa e trocar o padrão

**Description:** Como desenvolvedor, quero receber o ganho no comando normal
de testes assim que a paridade estiver demonstrada.

**Acceptance Criteria:**

- [ ] Rode a suíte padrão completa nos dois modos. Compare arquivos,
  resultados por caso e skips sob as mesmas condições. Demonstre que uma
  falha de compilação e uma falha de teste retornam saída diferente de zero.
- [ ] Faça uma auditoria única de cobertura com GCC/gcov para
  `src/donkey/`. Compare a união das linhas e dos ramos cobertos entre a
  revisão anterior à migração e a versão agrupada.
  Investigue qualquer redução e use os logs e o mapeamento do código gerado
  para distinguir mudanças de instrumentação de perdas reais de cobertura.
- [ ] Registre os quatro tempos de parede do protocolo abaixo e o número de
  compilações executadas em cada modo. Se uma meta falhar, identifique os
  grupos mais caros e ajuste sua composição antes de medir novamente.
- [ ] Após passar nas verificações de paridade e desempenho, faça
  `grouped` virar o padrão. Valide com `nimble test`, um comando por arquivo
  e o caminho `TEST_RUNNER=legacy`. Atualize a seção de testes do README com
  o uso do fallback.

## Functional Requirements

1. Descubra arquivos pelos alvos atuais, normalize e elimine duplicatas.
   Aplique as condições de ambiente e flags de cada perfil antes de compilar.
2. Mantenha o diretório de trabalho na raiz do repositório. Use os mesmos
   caminhos dos arquivos fonte, a configuração do projeto e as flags padrão
   `--mm:orc -u:withPostgres`. A localização de fixtures deve continuar válida.
3. Separe o cache por checkout, alvo ou grupo e perfil de compilação, incluindo
   a versão do compilador. Respeite `XDG_CACHE_HOME` e `JOBS`. Evite
   multiplicar o paralelismo externo pelo paralelismo do compilador C.
4. Um arquivo descoberto e ausente do manifesto continua no fluxo individual.
   Uma falha ao compilar um grupo presente no manifesto é reportada como erro.

## Technical Considerations

- Use o runner Bash existente e os frameworks de teste atuais. Preserve a
  compatibilidade do runner com Bash 3.2. A geração pode escrever apenas
  imports e um `case` por grupo.
- Para a auditoria, compile ambos os modos com o mesmo GCC e as opções
  `--lineDir:on --passC:--coverage --passL:--coverage`. Use
  `gcov --branch-probabilities --json-format` sobre os arquivos `.gcno`.
  Compare localizações do fonte Nim, pois os IDs de ramos gerados em C podem
  variar entre os builds. Guarde perfis e relatórios em cache separado.

## Success Metrics

- Meça `TEST_RUNNER=legacy JOBS=4 bash scripts/run_tests.sh` e o mesmo
  comando com `TEST_RUNNER=grouped`, sem shards, no mesmo checkout, com o
  mesmo compilador e dependências. Use um `XDG_CACHE_HOME` vazio e distinto
  para cada modo. Repita cada comando com o mesmo cache para a medição quente.
- O modo agrupado deve obter pelo menos **3×** nos dois cenários. Na máquina
  que registrou 822 s a frio e 199 s a quente, as metas práticas são
  **até 4 min a frio** e **até 1 min a quente**. Use a medição pareada como
  critério de aceite em outra máquina.
- A comparação final mostra todos os casos e skips esperados e nenhuma
  perda de cobertura atribuível à migração.

## Non-Goals

- A revisão do valor dos testes, a limpeza de testes vazios e a troca de
  frameworks ficam para trabalhos próprios.
- Mudanças em código de produção, dependências, versão do Nim e política de
  seleção por impacto seguem fora do escopo.

## Open Questions

O tamanho final dos grupos será decidido pelos tempos de compilação de US-009.
Comece com os limites e a ordem acima.
[/PRD]
