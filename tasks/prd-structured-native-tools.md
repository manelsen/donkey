# PRD: Camada Estruturada de Ferramentas Nativas do Donkey

## Overview
O Donkey hoje já possui um conjunto amplo de ferramentas nativas, mas a superfície principal ainda é fortemente inspirada em utilitários Unix expostos como API. Isso mantém o agente dependente de `bash` para composição, parsing textual e fluxos de automação que poderiam ser resolvidos com ferramentas orientadas a dados. O objetivo desta iniciativa é dar ao Donkey independência funcional: eliminar a família antiga de ferramentas Unix-like e substituí-la por uma nova camada nativa, estruturada e composável, com entrada e saída em JSON, schemas claros e comportamento previsível. A nova roda deve ser reinventada redonda: menos shell, menos ambiguidade, menos parsing textual, mais semântica de dados.

## Goals
- Reduzir drasticamente a necessidade de `bash` para operações de arquivos, texto, JSON, tabelas, arquivos compactados e HTTP.
- Substituir a família atual de tools Unix-like por uma nova camada nativa estruturada e coesa.
- Tornar a composição entre tools previsível, com entrada e saída em JSON e sem necessidade de `value_id` ou estado intermediário implícito.
- Melhorar segurança e auditabilidade ao remover parsing textual frágil e mini-DSLs desnecessárias.
- Alinhar schemas, descrições, dispatch e prompting para que o agente prefira as novas tools por padrão.
- Preservar precisão textual quando necessário, mas dentro de uma nova superfície coerente, não como remendo legado.

## Quality Gates

These commands must pass for every user story:
- `nimble build` - build completo do projeto
- Rodar os testes Nim relevantes para os módulos alterados
- Executar smoke manual das tools afetadas com casos felizes e casos de erro
- Quando aplicável, colher fixtures a partir de ferramentas `bash`/coreutils do sistema em diretórios de teste controlados, para validar compatibilidade funcional da nova camada

For tool and prompt stories, also include:
- Verificar que a descrição/schema da tool orienta o agente a preferi-la a `bash`
- Verificar que a saída JSON é estável e parseável
- Verificar que erros operacionais e erros de uso ficam distinguíveis

## User Stories

### [x] US-001: Fundar o contrato estruturado das novas tools
**Description:** Como mantenedor do Donkey, eu quero um contrato único para tools estruturadas para que composição, testes e prompting sigam um padrão coerente.

**Acceptance Criteria:**
- [x] Existe uma convenção formal para tools estruturadas com entrada JSON e saída JSON textual estável
- [x] O contrato define envelope mínimo de sucesso e erro para outputs estruturados
- [x] O contrato distingue claramente resultado de dados de erro operacional
- [x] O contrato define regras de compatibilidade entre tools para composição via JSON
- [x] O contrato não depende de `value_id` ou estado intermediário implícito

**Story Snapshot:**
- Introduzido o contrato `donkey.native_tool/v1` em `src/donkey/core/tooling/structured_tool_result.nim`
- Diferenciados `output`, `usage_error` e `operational_error` no envelope JSON estruturado
- Promovido `trkUsageError` ao domínio para estabilizar o vocabulário do contrato
- Cobertura adicionada em `tests/core/t_structured_tool_result.nim` e reforço em `tests/domain/t_message.nim`

## Execution Plan

### Parallel-safe now
- `US-002`: structured filesystem tools
- `US-003`: structured search and text tools
- `US-005`: structured archive and HTTP tools
- `US-004A`: core `json_query` and `table_query`

### Integrate later
- `US-004B`: make FS/search outputs flow naturally into `table_query`
- `US-006`: register and dispatch the new family
- `US-007`: teach the agent to prefer the new family
- `US-008`: remove the legacy Unix-like family

### Ownership boundaries
- `US-002` owns `src/donkey/app/tools/fs_tools.nim`
- `US-003` owns `src/donkey/app/tools/search_tools.nim` and `src/donkey/app/tools/text_tools.nim`
- `US-005` owns `src/donkey/app/tools/web_tools.nim` and any new archive helper module
- `US-004A` owns a new structured data module, e.g. `src/donkey/app/tools/data_tools.nim`
- `US-006` is the first integration story allowed to touch `src/donkey/domain/more_tools.nim`, `src/donkey/app/native_tools.nim`, and `src/donkey/core/tooling/native_tool_dispatch.nim`
- `US-007` is the first prompting story allowed to touch `src/donkey/app/prompt_building.nim` for structured-tool preference
- `US-008` is the cleanup/removal phase and should run last

### [x] US-002: Criar a nova família de tools de filesystem
**Description:** Como agente, eu quero ferramentas nativas de filesystem orientadas a dados para listar, ler, escrever, copiar, mover, criar e remover sem depender de shell.

**Acceptance Criteria:**
- [x] Existe uma tool estruturada para listar diretórios e arquivos com metadados (`path`, `kind`, `size`, `mtime`)
- [x] Existe uma tool estruturada para ler arquivos em formatos `text`, `lines`, `json` e metadados de bytes
- [x] Existe uma tool estruturada para escrever arquivos com modos `create`, `replace` e `append`
- [x] Existe uma tool estruturada para criar diretórios
- [x] Existe uma tool estruturada para copiar arquivo ou árvore
- [x] Existe uma tool estruturada para mover/renomear arquivo ou árvore
- [x] Existe uma tool estruturada para remover arquivo ou árvore
- [x] Todas respeitam o paddock/workspace atual e rejeitam paths fora do escopo permitido

**Story Snapshot:**
- Introduzido o núcleo estruturado de filesystem em `src/donkey/app/tools/fs_tools.nim`
- Cobertos `fs_list`, `fs_read`, `fs_write`, `fs_mkdir`, `fs_copy`, `fs_move` e `fs_remove`
- Paths da superfície estruturada passaram a ser relativos ao paddock, com raiz representada por `.`
- Gated green após integração com `t_fs_tools_structured`, `t_native_tools` e `nimble build`

### [x] US-003: Criar a nova família de tools de busca e transformação textual
**Description:** Como agente, eu quero buscar e transformar texto de forma estruturada para evitar parsing textual frágil e dependência de `grep`/`sed`.

**Acceptance Criteria:**
- [x] Existe uma tool estruturada de busca textual que retorna `path`, `line`, `text` e contexto relevante quando aplicável
- [x] Existe uma tool estruturada de substituição textual declarativa para casos simples e frequentes
- [x] Existe uma tool estruturada para leitura parcial/resumo de arquivo sem exigir shell
- [x] A nova superfície cobre os casos mais comuns hoje resolvidos com `grep`, `head`, `tail`, `wc`, `sort` e `sed`
- [x] Casos que não caibam nessa superfície permanecem explicitamente fora de escopo da tool, em vez de recriar shell disfarçada

**Story Snapshot:**
- Adicionados `performFindStructured` e `performGrepStructured` para busca estruturada em `search_tools.nim`
- Adicionados `readStructuredTextSlice` e `replaceStructuredText` em `text_tools.nim`
- A leitura parcial passou a retornar linhas ancoradas e o replace textual ficou deliberadamente literal nesta fase
- Gated green após integração com `t_structured_search_text_tools`, `t_native_tools` e `nimble build`

### [x] US-004A: Criar o núcleo estruturado para JSON e tabelas
**Description:** Como agente, eu quero operar diretamente sobre JSON e coleções genéricas para compor fluxos no estilo Nu sem depender de `jq` ou parsing manual.

**Acceptance Criteria:**
- [ ] Existe uma tool `json_query` com operações como `get`, `set`, `delete` e `merge`
- [ ] Existe uma tool `table_query` com operações como `select`, `where`, `sort` e `limit`
- [ ] Há testes cobrindo filtros, ordenação e projeção em arrays/objetos genéricos
- [ ] A documentação das tools deixa claro como compor resultados entre elas

### [x] US-004B: Integrar JSON e tabelas com as saídas estruturadas de FS e busca
**Description:** Como agente, eu quero consumir naturalmente as saídas estruturadas de filesystem e busca com `table_query` para compor fluxos sem transformação textual ad hoc.

**Acceptance Criteria:**
- [x] As saídas de listagem e busca podem ser consumidas por `table_query` sem transformação textual ad hoc
- [x] Há testes cobrindo filtros, ordenação e projeção em coleções reais de saída de tools
- [x] Os envelopes JSON produzidos por FS e busca permanecem compatíveis com o contrato `donkey.native_tool/v1`
- [x] A integração não introduz `value_id` nem estado intermediário implícito

**Story Snapshot:**
- `table_query` passou a aceitar envelopes estruturados completos via `input`, sem exigir extração manual prévia de arrays
- Entrou autodetecção de coleções em `data.rows`, `data.items`, `data.matches` e `data.lines`
- `rows_path` foi adicionado como override explícito quando a coleção desejada está em um caminho diferente
- Gated green com `t_data_tools`, `t_fs_tools_structured`, `t_structured_search_text_tools`, `t_native_tools` e `nimble build`

### [x] US-005: Criar tools estruturadas de arquivos compactados e HTTP
**Description:** Como agente, eu quero manipular arquivos compactados e requisições HTTP comuns sem cair em shell para tarefas repetitivas.

**Acceptance Criteria:**
- [ ] Existe uma tool para extrair arquivos compactados em diretório controlado
- [ ] Existe uma tool para criar arquivos compactados a partir de arquivos/árvores do workspace
- [ ] Existe uma tool HTTP estruturada que retorna `status`, `headers` e `body` em modo `text` ou `json`
- [ ] A tool HTTP respeita as políticas de allowlist e bloqueio de endereços privados já existentes
- [ ] Há smoke tests cobrindo respostas de sucesso, erro HTTP e bloqueio de URL

### [x] US-006: Alinhar dispatch, categorias e registro das novas tools
**Description:** Como mantenedor do runtime, eu quero que a nova família estruturada seja registrada e despachada como camada principal para manter o sistema coerente.

**Acceptance Criteria:**
- [x] As novas tools aparecem no registro nativo com descrições e schemas completos
- [x] A classificação de categorias nativas reflete a nova família estruturada
- [x] O dispatcher nativo reconhece e executa todas as novas tools
- [x] Outputs estruturados são serializados de forma consistente na história da conversa
- [x] Não há conflito nominal ambíguo entre tools novas e antigas

**Story Snapshot:**
- Registrada a família estruturada em `more_tools.nim` e `session_bootstrap.nim`
- Introduzida a categoria `ntckStructured` em `native_tool_dispatch.nim`
- Ligado o dispatcher nativo para `fs_*`, `text_*`, `json_query`, `table_query`, `http_fetch` e archive tools
- Validado ponta a ponta com `t_more_tools`, `t_native_tool_dispatch`, `t_session_bootstrap`, `t_native_tools` e `nimble build`

### [x] US-007: Ensinar o agente a preferir a nova superfície
**Description:** Como operador do Donkey, eu quero que o agente escolha as novas tools estruturadas antes de `bash` para reduzir comportamento frágil e improvisado.

**Acceptance Criteria:**
- [x] O prompt e/ou descrições de tools instruem explicitamente o agente a preferir as tools estruturadas a `bash`
- [x] Há orientação explícita para preferir JSON estruturado a parsing textual
- [x] Há orientação explícita sobre quando ainda usar `bash`
- [x] O agente consegue realizar um fluxo comum de FS + busca + JSON sem usar `bash`
- [x] Os testes/smokes de tool loop confirmam adoção da trilha estruturada em casos representativos

### [ ] US-008: Remover a família antiga de tools Unix-like
**Description:** Como mantenedor do Donkey, eu quero eliminar a superfície antiga para evitar duplicidade, ambiguidade e manutenção em paralelo.

**Acceptance Criteria:**
- [ ] Existe uma lista explícita das tools antigas que serão removidas
- [ ] `find`, `grep`, `sed`, `wc`, `head`, `tail`, `sort`, `cp`, `mv`, `rm` e `mkdir` deixam de ser a superfície primária
- [ ] O código morto ou legado relacionado a essa família é removido ou isolado de forma clara
- [ ] A documentação e o prompting não fazem mais referência às tools antigas como trilha principal
- [ ] Há testes cobrindo os fluxos substitutos com a nova família estruturada

## Functional Requirements
1. FR-1: O sistema deve expor uma nova família de tools nativas orientadas a dados com entrada e saída em JSON textual estável.
2. FR-2: A nova família deve cobrir listagem, leitura, escrita, busca, transformação, JSON, tabelas, arquivos compactados e HTTP.
3. FR-3: A nova família deve operar exclusivamente dentro do paddock/workspace permitido.
4. FR-4: A nova família deve distinguir claramente sucesso, erro operacional e erro de uso.
5. FR-5: A composição entre tools deve acontecer por passagem explícita de objetos JSON, sem `value_id`.
6. FR-6: O sistema deve manter uma trilha clara para edição textual precisa, mas alinhada ao novo modelo geral.
7. FR-7: O agente deve ser instruído a preferir a nova família a `bash` para os casos cobertos.
8. FR-8: As tools antigas de estilo Unix devem ser descontinuadas e removidas da trilha principal.
9. FR-9: O sistema deve manter `bash` apenas como escape hatch para casos não cobertos pela nova camada.
10. FR-10: O comportamento das novas tools deve ser validado com smoke tests e, quando cabível, fixtures colhidos via ferramentas do sistema em ambientes controlados.

## Non-Goals (Out of Scope)
- Recriar uma shell geral no estilo Bash, Nushell ou Elvish.
- Implementar pipelines com linguagem própria, parser próprio ou runtime de shell novo.
- Preservar compatibilidade nominal com a família antiga de tools por tempo indeterminado.
- Construir um mecanismo de `value_id`, dataset temporário ou memória estruturada de resultados nesta fase.
- Resolver todos os casos arbitrários hoje possíveis via `bash`.
- Alterar a arquitetura de sandboxing de processo nesta iniciativa.

## Technical Considerations
- A nova camada deve reutilizar o máximo possível da infraestrutura existente de dispatch, schemas, paddock e histórico de tools.
- Parte das implementações existentes pode ser reaproveitada internamente, mas a superfície pública deve ser redesenhada como produto novo.
- O desenho deve preservar o diferencial de precisão textual do Donkey sem contaminar todas as tools com hashline.
- Fixtures derivados de ferramentas do sistema devem ser usados apenas em diretórios de teste controlados, para evitar transformar o sistema externo em dependência sem controle.
- A remoção da família antiga deve ser coordenada com o prompt e com os testes de tool loop para evitar regressão no comportamento do agente.

## Success Metrics
- Queda significativa do uso de `bash` em fluxos comuns de arquivos, busca, JSON e HTTP.
- Adoção consistente da nova família pelo agente em smokes representativos.
- Redução de erros de parsing textual e de uso incorreto de tools Unix-like.
- Redução da ambiguidade no catálogo de tools.
- Cobertura de testes e smokes suficiente para que a nova camada substitua a antiga com confiança.

## Open Questions
- A ferramenta de edição textual precisa será redesenhada como parte da nova família ou mantida como componente especializado paralelo?
- Quais nomes finais da nova família melhor equilibram clareza e concisão?
- Qual envelope JSON final melhor distingue resultado útil, preview e erro sem criar verbosity excessiva?
- `bash` deve continuar visível ao agente por padrão ou passar a exigir condições mais explícitas no prompting?
- A remoção da família antiga será feita em uma única leva ou por blocos funcionais?
