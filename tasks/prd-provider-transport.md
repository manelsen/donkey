[PRD]
# PRD: Transporte OpenAI-compatible e descritores de provider

> **Executor:** agente autônomo. Leia este documento inteiro antes de começar.
> Execute as histórias **na ordem**. Cada história termina com os quality gates
> verdes e um commit próprio. Não abra a história seguinte com a anterior
> vermelha.

## 1. Contexto

O Donkey tem cinco adapters que falam o mesmo protocolo OpenAI e três deles
reimplementam a mesma serialização:

| Provider | Usa `openai_pure`? | Serializa mensagens de novo? |
|---|---|---|
| OpenAI | sim | não |
| DeepSeek | sim | não |
| MiniMax | só `parseResponseFrom` | **sim** (`toJson`/`buildBody` próprios) |
| Zhipu | não | **sim** (e parser próprio) |
| OpenRouter | não | **sim** + SSE/tool-delta próprio |

O custo disso é concreto: a rodada que adicionou imagem teve de tocar em
`openai_pure.nim`, `anthropic.nim`, `gemini_pure.nim`, `zhipu.nim` e
`minimax.nim`. Além disso, `domain/providers/quirks.nim` (mapeamento de papel e
alternância) **não tem chamador de produção**; o mapeamento real está
duplicado em `gemini_pure.geminiRole`.

O `hermes-agent` resolve isso com uma camada de **transporte** explícita:
`agent/transports/chat_completions.py` é o transporte padrão para todo provider
OpenAI-shaped, com os desvios absorvidos em hooks; `providers.py` carrega um
`HermesOverlay` (transporte, auth, base URL, env vars, aggregator) e
`runtime_provider.py` resolve `provider → (api_mode, base_url)`.

A missão é trazer **a forma**, não o código: descritor + transporte + hooks
pequenos, em Nim idiomático, preservando a arquitetura hexagonal.

## 2. Objetivos

1. Uma **tabela de descritores** por provider como fonte única de identidade
   (transporte, env vars, base URL, modelo default, auth, aggregator).
2. **Um** adapter OpenAI-compatible parametrizado por perfil; os adapters por
   provider viram construtores de perfil, não cópias do serializador.
3. Uma **suíte de conformidade** tabelada (request/response) para todos os
   perfis compatíveis.
4. Zero mudança de comportamento observável: mesmos endpoints, headers,
   payloads e parsing; os testes existentes continuam passando sem edição.
5. Remover a duplicação e o código inerte (`quirks.nim`) ao final da migração.

## 3. Fora de escopo

- OAuth, device code, AWS/Vertex/Bedrock e qualquer `auth_type` além de
  `api_key`. O campo `authType` entra no descritor, mas o comportamento é o de
  hoje (chave estática).
- Reescrever os transportes Anthropic e Gemini: eles **não** são OpenAI-shaped e
  continuam com `anthropic_pure`/`gemini_pure`.
- Novos providers, mudanças em smart routing, cooldown, pool de credenciais ou
  streaming.
- Mudanças de UI, canais, ferramentas ou dashboard.
- Copiar código Python do hermes. Transfere-se o desenho, não a implementação.
- Criar um `case` gigante dentro de um único adapter. O ganho vem de dados +
  hooks.

## 4. Quality gates

Obrigatórios ao fim de **toda** história:

```bash
bash scripts/check_boundaries.sh
nimble build -y
JOBS=6 bash scripts/run_tests.sh
git diff --check
```

Regras adicionais, sem exceção:

- TDD: escreva o teste, confirme que **falha**, implemente, confirme que passa.
- Lógica pura em `domain/` ou `core/` como `func`; o adapter só faz ligação.
- Proibido `raise` fora de adapter; I/O falível devolve `Result[T, string]`.
- Nenhum teste novo usa rede, provider real ou Docker.
- Nenhum teste existente é editado para “acomodar” a mudança; se um teste
  precisar mudar, o comportamento mudou e a história deve dizer isso.
- Se o worktree estiver sujo ao começar, **pare** e registre; não use stash,
  reset ou checkout sobre trabalho alheio.

### 4.1 Ciclo de execução — TDD não é opcional

Cada história segue exatamente esta ordem, sem atalho:

1. Escrever **um** arquivo de teste (ou um bloco novo nele) e rodá-lo.
2. **Mostrar a falha** no relato da história: a saída do `run_tests.sh` com o
   erro esperado (módulo ausente, símbolo inexistente ou asserção falhando).
   Teste que passa antes da implementação está errado e deve ser corrigido.
3. Implementar o mínimo para o teste passar.
4. Rodar o mesmo teste até verde.
5. Rodar os quality gates completos.
6. Commitar a história com a evidência do vermelho → verde no corpo do commit
   (duas linhas bastam: o erro inicial e o resultado final).

Exceção única: **refactor puro sem mudança de comportamento** (US-007, US-008,
US-009 e a parte de fiação da US-010). Nesses casos o teste é de
**caracterização**: escreve-se primeiro, ele fica verde antes e depois, e o
commit diz “characterization, green before/after”. O vermelho continua
obrigatório para qualquer história que adicione ou mude comportamento.

Proibido:

- Escrever implementação antes do teste falhar (fora da exceção acima).
- Editar um teste existente para “acomodar” a mudança. Se o comportamento
  mudou, a história diz isso explicitamente.
- Rodar a suíte inteira como primeiro sinal: o primeiro sinal é o teste novo
  falhando sozinho.

### 4.2 Paralelização

Pode-se paralelizar sem limite o que **não compartilha arquivos**:

- pesquisa e leitura (inventário de providers, testes, hooks do hermes);
- redação de testes de histórias diferentes, desde que cada uma seja dona do
  seu arquivo de teste;
- implementação de histórias com **conjuntos de arquivos disjuntos**.

Regras de coordenação:

- `src/donkey/domain/providers/compat.nim` e `openai_pure.nim` têm **um único
  escritor** por vez. A US-002 é o portão serializado; só depois dela as
  migrações de Zhipu/MiniMax/OpenRouter podem correr em paralelo.
- Cada subagente declara os arquivos que possui; ninguém edita arquivo de
  outro.
- A suíte completa e os commits são **sequenciais na sessão principal**.
  Testes direcionados podem rodar em paralelo; `run_tests.sh` completo não,
  porque os binários de teste colidem.
- O TDD continua obrigatório por história: o vermelho é mostrado antes da
  implementação, mesmo quando a implementação roda em paralelo.

## 5. Preparação (antes da US-001)

1. `cd ~/git/donkey && git status --short`. Em missão **paralela**, o worktree
   contém mudanças de outros donos: pare apenas se houver alteração em um
   arquivo que **você** possui. Nunca use stash, reset ou checkout sobre
   trabalho alheio.
2. `git fetch origin && git switch master && git pull --ff-only` (uma única vez,
   antes de abrir a missão; durante a missão ninguém troca de branch).
3. Criar a branch `feat/provider-transport`.
4. Registrar no commit de abertura que este PRD é a fonte de verdade da
   missão.

## 6. Histórias

### US-001: Tabela de descritores de provider

**Descrição:** Como mantenedor, quero uma fonte única de metadados por provider
para eliminar os `case` paralelos de env/default model e preparar o transporte.

**Critérios de aceite:**
- [ ] Criar `src/donkey/domain/providers/descriptors.nim` com
      `ProviderDescriptor` (`id`, `transport`, `authType`, `envNames`,
      `baseUrl`, `baseUrlEnv`, `defaultModel`, `aggregator`) e
      `providerDescriptor*(id: string): Option[ProviderDescriptor]`.
- [ ] A tabela cobre exatamente os providers de hoje: `openrouter`, `openai`,
      `deepseek`, `ollama`, `groq`, `opencode-go`, `zen`, `anthropic`,
      `zai-anthropic`, `gemini`, `minimax`, `zai`, `zai-coding`.
- [ ] `buildProviderSpec` (`app/session_bootstrap.nim`) resolve env names e
      modelo default pelo descritor, preservando a ordem de fallback atual
      (ex.: `ZAI_ANTHROPIC_API_KEY` → `ANTHROPIC_AUTH_TOKEN` →
      `ZAI_CODING_API_KEY` → `ZAI_API_KEY` → `ZHIPU_API_KEY`).
- [ ] `detectProviderAvailability` usa os mesmos `envNames` do descritor.
- [ ] `ProviderSpec` continua com os mesmos campos públicos; nenhum call site
      muda.
- [ ] Teste de paridade em `tests/domain/providers/t_descriptors.nim`:
      para cada provider, com env controlado, `buildProviderSpec` e
      `detectProviderAvailability` produzem o mesmo resultado da tabela
      legada; provider desconhecido cai em `zai-coding`.
- [ ] `rg -n "getEnv\\(\"(OPENROUTER|OPENAI|DEEPSEEK|GROQ|GEMINI|MINIMAX|ZAI|ZHIPU|ANTHROPIC|OPENCODE)"`
      em `session_bootstrap.nim` não encontra mais resolução de chave por
      provider (o pool de credenciais continua sendo a única leitura de env
      de chave).

**Notas:** `baseUrl`/`baseUrlEnv` entram agora porque são metadados de
identidade, mas só passam a ser consumidos nas histórias de migração; não
altere endpoints nesta história.

### US-002: Perfil compatível + OpenAI/DeepSeek

**Descrição:** Como mantenedor, quero um perfil declarativo para o transporte
OpenAI-compatible para que texto, tools e imagem sejam serializados uma vez só.

**Critérios de aceite:**
- [ ] Criar `src/donkey/domain/providers/compat.nim` com `CompatProfile`
      (endpoint, headers extras, extras de payload/reasoning/stream, quirks de
      wire, suporte a imagem) e
      `buildCompatRequestBody(profile, model, req, stream): JsonNode`. O SSE
      continua no adapter; o perfil não finge um hook que não existe.
- [ ] `openai.nim` e `deepseek.nim` usam o novo builder e o perfil default;
      nenhum dos dois mantém serialização própria.
- [ ] Testes golden em `tests/domain/providers/t_compat_openai.nim` para:
      system + texto; tools e `tool_choice`; imagem em data URL; mensagem de
      tool result.
- [ ] `tests/provider/t_openai.nim` e os testes de deepseek continuam
      passando **sem edição**.

### US-003: Migrar Zhipu para o perfil

**Descrição:** Como mantenedor, quero que o Zhipu expresse só os seus desvios
(`thinking`, native tools) e não uma cópia do serializer.

**Critérios de aceite:**
- [ ] `newZhipuAdapter` constrói o adapter compatível com perfil Zhipu
      (endpoint `api.z.ai/...`, `thinking` quando `req.reasoning`, native tools
      declaradas).
- [ ] `zhipu.nim` deixa de ter `toJson`/`buildBody` locais; o parser de
      resposta permanece no adapter (`parseZhipuResponse`), documentado, porque
      o formato de resposta tem diferenças próprias.
- [ ] Testes golden do perfil Zhipu em `tests/domain/providers/t_compat_zhipu.nim`
      (thinking on/off, tools nativas, imagem).
- [ ] `tests/provider/t_zhipu.nim` continua passando sem edição.

### US-004: Migrar MiniMax para o perfil

**Descrição:** Como mantenedor, quero que o MiniMax reuse integralmente o
transporte OpenAI-compatible, expressando só `reasoning_split`.

**Critérios de aceite:**
- [ ] `minimax.nim` usa o builder compatível e `openai_pure.parseResponseFrom`;
      não mantém `toJson`/`buildBody`.
- [ ] Perfil MiniMax: `reasoning_split: true`, endpoint e modelo default
      preservados.
- [ ] Golden test com `reasoning_split` e tool calls.
- [ ] `tests/provider/t_minimax.nim` continua passando sem edição.

### US-005: Migrar OpenRouter para o perfil, mantendo o SSE no módulo

**Descrição:** Como mantenedor, quero que os headers obrigatórios fiquem no
perfil, sem duplicar a serialização de mensagens; o parser SSE continua no
adapter, onde é testado.

**Critérios de aceite:**
- [ ] `openrouter.nim` usa o builder compatível; remove `toJson`/`buildBody`.
- [ ] Perfil OpenRouter: `HTTP-Referer` e `X-Title`, endpoint e modelo default.
- [ ] O parser SSE (`OpenRouterSseChunk`) permanece funcional no módulo; os
      testes de streaming existentes passam sem edição e o caminho de produção
      (`complete`/`makeStreamFn`) chama os mesmos builders testados.
- [ ] Golden test do request OpenRouter (inclui imagem, tools e reasoning).

### US-006: Suíte de conformidade tabelada

**Descrição:** Como mantenedor, quero um único teste de conformidade por perfil
para que adicionar um provider não copie asserções.

**Critérios de aceite:**
- [ ] Criar `tests/domain/providers/t_compat_conformance.nim` com uma tabela de
      perfis e os mesmos casos (system/texto, tools, tool result, imagem,
      reasoning) aplicados a todos.
- [ ] O teste falha quando um perfil perde um hook obrigatório (ex.: Zhipu sem
      `thinking`, MiniMax sem `reasoning_split`).
- [ ] Nenhuma asserção de conformidade duplicada nos testes por adapter.

### US-007: Remover `quirks.nim`

**Descrição:** Como mantenedor, quero uma única fonte de mapeamento de papel e
alternância; `quirks.nim` está inerte e duplicado.

**Critérios de aceite:**
- [ ] `rg -n "quirks" src tests` não encontra imports; o mapeamento de papel
      vive nos perfis/transportes.
- [ ] Remover `src/donkey/domain/providers/quirks.nim` e
      `tests/domain/providers/t_quirks.nim`.
- [ ] Nenhum comportamento de Gemini/Anthropic muda (`gemini_pure` e
      `anthropic_pure` são os donos).

### US-008: runtime_builder e catálogo a partir dos descritores

**Descrição:** Como mantenedor, quero que endpoints, modelos default e aliases
não sejam repetidos no factory nem no catálogo.

**Critérios de aceite:**
- [ ] `runtime_builder.nim` resolve endpoint por `descriptor.baseUrl` (quando o
      provider não tem override próprio), modelo default por
      `descriptor.defaultModel`, aliases por `descriptor.aliases` e o fallback
      desconhecido por `defaultProviderDescriptor`.
- [ ] `model_catalog.nim` resolve nomes de env por `descriptor.envNames` em vez
      das cadeias próprias (linhas ~605–639).
- [ ] O host do catálogo (OpenRouter/Groq/Anthropic/Gemini/Z.ai) pode continuar
      explícito quando o path de `/models` não for derivável do chat; documentar
      o que fica fora.
- [ ] Nenhum endpoint, default model ou alias duplicado em
      `runtime_builder.nim`; `rg` confirma.
- [ ] A resolução de credencial do catálogo passa a ser a do descritor. O
      delta observável para `zai` (antes `ZAI_CODING_API_KEY`/`ZHIPU_API_KEY`,
      agora `ZAI_API_KEY`) fica registrado no commit como consolidação
      deliberada, alinhada a `buildProviderSpec`.
- [ ] Testes existentes de `t_runtime_builder` e `t_model_catalog` passam sem
      edição; novo teste de paridade cobre um provider por família.

### US-009: doctor, setup, service handler, TUI e custo a partir dos descritores

**Descrição:** Como mantenedor, quero que toda lista de providers visível ao
operador venha da tabela, sem listas velhas.

**Critérios de aceite:**
- [ ] `doctor.nim`, `setup_wizard.nim`, `service_handler.nim`,
      `admin_tui.nim` e `src/donkey.nim` (fallback OpenRouter, lista de custo)
      iteram `providerDescriptors()`; nenhuma lista de ids/env própria.
- [ ] A lista do doctor deixa de omitir groq/ollama/opencode-go/zen.
- [ ] Teste de paridade: para cada descritor, o doctor e o setup expõem o mesmo
      conjunto de providers e o primeiro env var de cada um.
- [ ] Textos/labels podem continuar explícitos; só a identidade e o env vêm da
      tabela.
- [ ] Nenhuma mudança de comportamento além de listas mais completas.

### US-010: Documentar a arquitetura e fechar a missão

**Descrição:** Como mantenedor, quero que a próxima pessoa entenda a divisão
descritor → transporte → perfil.

**Critérios de aceite:**
- [ ] `docs/topics/providers.md` ganha a seção “Arquitetura de providers” com a
      tabela descritor/transporte/perfil e o fluxo de uma requisição.
- [ ] A seção de imagem cita que o perfil é o único lugar que decide o
      envelope.
- [ ] `rg` confirma zero `toJson`/`buildBody` duplicados em
      `adapters/provider/{zhipu,minimax,openrouter,openai,deepseek}.nim`.
- [ ] Atualizar a seção 11 da V3/V4? **Não**: a V4 já é a fonte; registrar no
      commit que a missão não muda o placar (é refactor de arquitetura, não de
      cobertura).

## 7. Requisitos funcionais

- **FR-1:** O descritor é a única fonte de `transport`, `envNames`,
  `defaultModel` e `baseUrl`/`baseUrlEnv` por provider.
- **FR-2:** `buildProviderSpec`, `detectProviderAvailability` e o futuro
  `runtime_builder` consomem o descritor; nenhum deles repete a lista de env
  vars.
- **FR-3:** Todo provider `openai_chat` usa um único builder de request.
- **FR-4:** Diferenças por provider são expressas como dados/hook no perfil
  (headers, extras de payload, role map, imagem, SSE, sanitização de tools).
- **FR-5:** `ProviderPort`, `ProviderCaps` e o roteamento não mudam nesta
  missão.
- **FR-6:** Os testes de conformidade são tabelados por perfil; um provider novo
  adiciona uma linha, não uma suíte.
- **FR-7:** Nenhuma chamada de rede real nos testes.

## 8. Não-objetivos

- Unificar Anthropic/Gemini no transporte OpenAI: eles têm protocolo próprio.
- Implementar `responses`/`bedrock_converse`/`gemini` como transportes
  adicionais nesta missão.
- OAuth ou pool de credenciais (já entregues; não regredir).
- Mudar comportamento de streaming, retries, roteamento ou cooldown.
- Refatorar `smart_routing` ou `ProviderCaps`.

## 9. Considerações técnicas

- Hexagonal: `descriptors.nim`, `compat.nim` e os perfis são **puros**; o
  adapter compatível é a única camada que toca HTTP. Nenhum `raise` novo fora
  de adapter.
- O adapter compatível implementa `complete`/`stream` do `ProviderPort` e
  recebe um `CompatProfile` por valor; nada de herança.
- O SSE do OpenRouter permanece um parser separado exposto por hook; não
  generalizar antes de existir um segundo dialeto.
- `ProviderSpec` não ganha `baseUrl` nesta missão; endpoints continuam nos
  construtores até a história que migra cada provider, para não misturar
  metadado com comportamento.
- Migração provider a provider, um commit por história; nunca um big bang.
- Se um teste existente precisar mudar em US-002..US-005, pare: o requisito é
  zero mudança de comportamento.

## 10. Métricas de sucesso

- 0 cópias de `toJson`/`buildBody` em `adapters/provider/` para providers
  OpenAI-shaped.
- Adicionar um provider compatível novo = 1 linha na tabela + 1 perfil + 1 linha
  na conformidade (sem tocar em serialização).
- Suíte total continua verde (baseline: **242 passed, 0 failed**), sem edição
  de testes existentes.
- `check_boundaries.sh` continua 0; nenhum import novo de adapter em
  `domain/core`.

## 11. Questões em aberto

- O hook de SSE deve ficar no perfil ou num `StreamDialect` separado? Decidir
  em US-005 pelo tamanho real; se for só OpenRouter, fica no perfil.
- O `transport` do descritor deve ser enum fechado ou string? Preferir enum
  (`ptOpenAiChat`, `ptAnthropicMessages`, `ptGemini`) para o compilador ajudar;
  strings só na borda de config.
- `zai-coding` e `zai` compartilham endpoint/credenciais; manter dois
  descritores (como hoje) para não mudar identidade pública.
[/PRD]
