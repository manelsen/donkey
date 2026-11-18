[PRD]
# PRD: Adapter compat, breadth de providers e limites (V4, prioridade 4)

> **Executor:** agente autônomo. Leia tudo e execute as histórias **na ordem**; cada uma termina com gates verdes e commit próprio, e a seguinte não abre com a anterior vermelha.
> **Dependência dura:** `tasks/prd-provider-transport.md` (US-001, US-002, US-006, US-008, US-009) **mergeado**. O transporte entrega descritor, `CompatProfile` e conformidade, mas **não** um adapter genérico: a US-001 desta missão o cria e já o prova com a NVIDIA. Nenhum adapter por provider é criado.

## 1. Contexto

A V4 (`COBERTURA_HERMES_VS_DONKEY_V4.md`, §6, prioridade 4) mede Providers em 57% contra 98%, distância 41. Por decisão do mantenedor (18/11/2026), **OAuth device-code fica fora de escopo** como TODO de longo prazo: os providers do Donkey são API-key. A V4 §3.2 estava desatualizada ao dizer que nenhum provider expõe o fluxo (`nous` expõe), mas o client id público é do Hermes; o registro técnico fica em §6.1 para o futuro. Esta missão entrega o adapter genérico que falta, breadth OpenAI-compatible verificado e metadados de limite, sem transporte novo e sem UI.

| Provider | Env | Endpoint | Modelo default | Quirk | Visão |
|---|---|---|---|---|---|
| `nvidia` (NIM) | `NVIDIA_API_KEY` | `https://integrate.api.nvidia.com/v1/chat/completions` | `nvidia/nemotron-3.5-super-vl-120b-a12b` | tool message sem `name`; billing header | **sim** (`providers.md:517-518`) |
| `alibaba` (DashScope) | `DASHSCOPE_API_KEY` | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions` | `qwen3.8-max` | path `compatible-mode` | não verificada |
| `fireworks` | `FIREWORKS_API_KEY` | `https://api.fireworks.ai/inference/v1/chat/completions` | `accounts/fireworks/models/kimi-k2p6` (escolha do Donkey; US-004) | headers de atribuição; schema estrito | não |

Evidência (read-only em `/home/micelio/git/hermes-agent`): NVIDIA em `providers.py:62`, `plugins/model-providers/nvidia/__init__.py:9-32`, `providers.md:513-573` (visão em `517-518`), `models_catalog_static.py:246-250`, `auxiliary_client.py:937`; Alibaba em `auth.py:212-213`, `plugins/model-providers/alibaba/__init__.py:13-25`, `providers.md:36,259-260`, `models_catalog_static.py:209-212`; Fireworks em `providers.py:75-76`, `plugins/model-providers/fireworks/__init__.py:9-42`, `providers.md:227-229,293`, `chat_completions.py:40-46,288`. Fato que não bater na verificação da história **para** a história.

## 2. Objetivos

1. Um `CompatAdapter` genérico (headers/endpoint/corpo/parser) e a NVIDIA provando-o ponta a ponta.
2. Alibaba e Fireworks só com descritor+perfil puro; nenhum adapter por provider.
3. Limites verificados numa fonte pura, com efeito real no roteamento e nas superfícies.
4. Zero regressão; testes existentes intocados, exceto a linha aditiva declarada na conformidade.

## 3. Fora de escopo

- Bedrock/Vertex/Azure nativos; OAuth Copilot/Codex; `qwen-oauth`/`minimax-oauth`; OAuth device-code (TODO de longo prazo, §6.1).
- Enriquecimento por `/models` ao vivo, fetch de models.dev, consumidor de `baseUrlEnv`.
- Mudar a forma de `ProviderCaps` (não há campo de visão); UI/dashboard/setup novos; canais, ferramentas, memória.
- Copiar código Python; transfere-se o desenho.

## 4. Quality gates

Obrigatórios ao fim de **toda** história:

```bash
bash scripts/check_boundaries.sh
nimble build -y
JOBS=6 bash scripts/run_tests.sh
git diff --check
```

Regras adicionais, sem exceção:

- TDD: teste primeiro, **falha mostrada**, implementação mínima, verde.
- Lógica pura em `domain/`/`core/` como `func`; adapter só faz I/O.
- Proibido `raise` fora de adapter; I/O falível devolve `Result[T, string]`.
- Nenhum teste novo usa rede, provider real ou Docker; nenhum teste existente é editado, **exceto** a linha aditiva de `t_compat_conformance.nim` declarada na US-001/003/004.
- Worktree sujo em arquivo que **você** possui: pare e registre; nunca use stash, reset ou checkout sobre trabalho alheio.

### 4.1 Ciclo de execução — TDD não é opcional

Por história: escrever **um** teste e rodá-lo; mostrar a falha (módulo/símbolo ausente ou asserção) no relato; implementar o mínimo; verde; gates; commit com o vermelho → verde no corpo. A exceção de caracterização vale só para refactor puro; **toda** história aqui adiciona comportamento, então todas exigem vermelho.

### 4.2 Paralelização e posse de arquivo

- Pesquisa e redação de testes em paralelo; implementação só com arquivos disjuntos; cada subagente declara o que possui.
- Novos e exclusivos: `adapters/provider/compat_adapter.nim` + `tests/adapters/provider/t_compat_adapter.nim` (US-001), `domain/providers/model_limits.nim` (US-002), `domain/providers/profile_{nvidia,alibaba,fireworks}.nim` (uma por história). **Não** crie `adapters/provider/{nvidia,alibaba,fireworks}.nim`.
- Escritores únicos, um por vez: `compat.nim` (só US-001, aditivo), `descriptors.nim`/`provider_defaults.nim`/`runtime_builder.nim` (US-001 → US-003 → US-004), `t_compat_conformance.nim` (linhas aditivas).
- `smart_routing.nim` e `session_bootstrap.nim` são compartilhados com **ferramentas** (`requestApproxChars`, `buildCompleteFn`) e **multiagente**: espere aqueles PRDs liberarem os arquivos; depois esta missão é a única escritora e edita por história. Se estiverem ativos, **pare**.
- A US-002 é arquivo novo e pode ser escrita em paralelo à US-001; o merge é antes da US-005. `provider_catalog.nim` só tem escritor na US-005; suíte e commits são sequenciais.

## 5. Preparação (antes da US-001)

1. `git status --short`; pare se houver alteração em arquivo seu.
2. `git fetch origin && git switch master && git pull --ff-only`; branch `feat/provider-breadth`.
3. Confirmar no `master` descritor, `compat.nim` e conformidade do `prd-provider-transport`; se faltar, **pare**. Commit de abertura aponta este PRD como fonte de verdade.
4. OAuth device-code está **deferido por decisão** (TODO de longo prazo); a missão não depende dele. OAuth Copilot/Codex e Bedrock/Vertex/Azure nativos também ficam fora e os 41 pontos não são fechados aqui.

## 6. Histórias

### US-001: `CompatAdapter` genérico + vertical slice NVIDIA

**Descrição:** fechar a lacuna do transporte (adapter, headers e endpoint vindos do perfil) e provar numa NVIDIA real, com visão.

**Verificação:** `git -C /home/micelio/git/hermes-agent log --oneline -5 -- plugins/model-providers/nvidia/__init__.py hermes_cli/providers.py`; conferir `providers.py:62`, `nvidia/__init__.py:27-32`, `providers.md:513-573` — inclusive “supports text and image inputs, reasoning, and tool calls” em `providers.md:517-518`.

- [ ] `compat.nim` ganha `reasoningOffExtras*: JsonNode` (aditivo), mesclado quando `not req.reasoning`; é a única edição no arquivo e ninguém mais o toca. Novo `tests/domain/providers/t_compat_reasoning_off.nim` prova o merge com `false` e a ausência com `true`.
- [ ] Criar `adapters/provider/compat_adapter.nim` com `CompatAdapter` (`apiKey`, `model`, `providerName`, `profileFn: proc(): CompatProfile {.gcsafe, nimcall.}`), `newCompatAdapter*`, `buildBody*` (via `buildCompatRequestBody`), puros `requestHeaders*`/`requestUrl*`/`parseCompatBody*`, `complete*` (headers de `requestHeaders`, POST em `requestUrl`, parse por `parseCompatBody`, que usa `openai_pure.parseResponseFrom`) e `makeStreamFn*` (reusa `parseOpenAISseLine`; SSE de conteúdo + `[DONE]`; `delta.reasoning` fica fora, §11). `caps*` devolve `maxContextTokens=0` até a US-002. Nada de JsonNode capturado no closure.
- [ ] `tests/adapters/provider/t_compat_adapter.nim`: `requestHeaders` inclui `Authorization`, `Content-Type` e `profile.extraHeaders`; `requestUrl` = `profile.endpoint`; corpo = `buildCompatRequestBody`; `parseCompatBody` ok e erro; `streamFn != nil`; sem rede.
- [ ] NVIDIA: `DefaultModelNvidia*` em `provider_defaults.nim`; descritor (`ptOpenAiChat`, `NVIDIA_API_KEY`, endpoint da tabela, `baseUrlEnv: "NVIDIA_BASE_URL"`, aliases `nvidia-nim`/`nim`/`build-nvidia`, sem `nemotron`); `domain/providers/profile_nvidia.nim` com `nvidiaCompatProfile*()`: `quirks.toolResultName = false`, `includeReasoningField = false` (campo do Donkey), `supportsImages = true`, `extraHeaders = @[("X-BILLING-INVOKE-ORIGIN", "Donkey")]`.
- [ ] Fiação: `runtime_builder.nim` (usa `newCompatAdapter` + perfil), `ProviderAvailability.nvidia`, `isAvailable`, `detectProviderAvailability`, `availableProviderNames`; criar `tests/app/t_provider_breadth_surface.nim` provando que doctor/setup/TUI/custo (transporte US-009) listam `nvidia` sem lista própria.
- [ ] `tests/domain/providers/t_compat_nvidia.nim`: golden system+texto, tools, tool result **sem** `name`, **imagem preservada** (data URL), `reasoning=true` sem `include_reasoning`/`reasoning_effort`, header ≠ `HermesAgent`; resposta com `reasoning_content` via `openai_pure`.
- [ ] `tests/provider/t_nvidia.nim`: `buildProviderBundle` com `streamFn != nil` (não é fallback Zhipu), modelo default e `caps().toolCalling`; **uma linha nova** em `t_compat_conformance.nim` (aditiva, nenhuma asserção existente muda).

### US-002: `modelLimits` puro (4a)

**Descrição:** limites verificados com procedência, antes de qualquer catálogo ou rota.

- [ ] Criar `domain/providers/model_limits.nim` com `ModelLimits` (`contextWindow`, `maxOutputTokens`, `supportsImages`, `supportsTools`, `source`, `sourceRef`), `ModelLimitSource` (`mlsVerified`/`mlsDescriptor`/`mlsUnknown`) e `modelLimits*(provider, model): ModelLimits`.
- [ ] Precedência: entrada exata `(provider, model)` → default do descritor (0/false) → **desconhecido conservador: tudo 0/false**; ausência nunca vira promessa (FR-3). `func` pura, sem I/O.
- [ ] Tabela verificada: NVIDIA `supportsImages=true`, `supportsTools=true` (`providers.md:517-518`), `maxOutputTokens=16384` (`nvidia/__init__.py:31`), `contextWindow=0` (sem fonte); Alibaba/Fireworks só entram com fato verificado — caso contrário `mlsUnknown` com `sourceRef` vazio.
- [ ] `tests/domain/providers/t_model_limits.nim`: precedência, desconhecido 0/false, `sourceRef` preenchido em `mlsVerified`, determinismo; nenhum acesso a catálogo.

### US-003: Alibaba DashScope (Qwen Cloud)

**Descrição:** Qwen Cloud por chave, reusando o `CompatAdapter` da US-001 com perfil puro.

**Verificação:** `auth.py:212-213`, `alibaba/__init__.py:22-25`, `providers.md:36,259-260`, `models_catalog_static.py:209-212`.

- [ ] `DefaultModelAlibaba* = "qwen3.8-max"` (primeiro da lista curada; `providers.md:260` usa `qwen3.5-plus` — divergência em §11); descritor `alibaba` (`ptOpenAiChat`, `DASHSCOPE_API_KEY`, endpoint da tabela, `baseUrlEnv: "DASHSCOPE_BASE_URL"`, aliases `dashscope`/`alibaba-cloud`/`aliyun`, sem `qwen`).
- [ ] `domain/providers/profile_alibaba.nim` com `alibabaCompatProfile*()`: `supportsImages = false` (não verificada), `includeReasoningField = false` (quirk do Donkey), sem `payloadExtras`. `runtime_builder` constrói `newCompatAdapter`; **nenhum adapter novo**.
- [ ] `preserve_thinking` **não** entra: o transporte não reenvia `reasoning`; dívida em §11.
- [ ] Fiação de runtime/superfície como na US-001; `tests/domain/providers/t_compat_alibaba.nim` (golden, imagem suprimida, sem `include_reasoning`) e `tests/provider/t_alibaba.nim` (bundle não-fallback, endpoint sem barra dupla); linha aditiva na conformidade.

### US-004: Fireworks AI

**Descrição:** Fireworks com headers, default explicitamente escolhido e desligamento de reasoning.

**Verificação:** `providers.py:75-76`, `fireworks/__init__.py:9-42`, `providers.md:227-229,293`, `chat_completions.py:40-46,288`.

- [ ] `DefaultModelFireworks* = "accounts/fireworks/models/kimi-k2p6"` com comentário: **escolha do Donkey** a partir de `fallback_models[0]`, não default do Hermes (`glm-5p2` é `default_aux_model`); descritor `fireworks` (`ptOpenAiChat`, `FIREWORKS_API_KEY`, endpoint, `baseUrlEnv: ""`, aliases `fireworks-ai`/`fw`).
- [ ] `domain/providers/profile_fireworks.nim`: `fireworksCompatProfile*()` com `HTTP-Referer`, `X-Title: "Donkey"`, `User-Agent: "Donkey"`, `supportsImages = false`, `includeReasoningField = false` e `reasoningOffExtras = {"reasoning_effort": "none"}` — Hermes emite `"none"` quando desabilitado (`fireworks/__init__.py:23-24`); `req.reasoning=true` não emite nada (sem esforço no `CompletionRequest`). `runtime_builder` usa `newCompatAdapter`.
- [ ] Golden `tests/domain/providers/t_compat_fireworks.nim`: corpo só com chaves OpenAI, `reasoning=false` → `reasoning_effort: "none"`, `reasoning=true` → sem `reasoning_effort`/`reasoning`/`include_reasoning`, imagem suprimida; `tests/provider/t_fireworks.nim` (bundle não-fallback, default); linha aditiva na conformidade.

### US-005: Catálogo, roteamento e `ProviderCaps` (4b)

**Descrição:** dar efeito real a `modelLimits`, sem reordenar o que existe.

- [ ] `provider_catalog.buildDefaultCatalog` registra entradas dos três usando `modelLimits`; `CompatAdapter.caps` lê `maxContextTokens` de `modelLimits` (só esse campo flui; sem visão em `ProviderCaps`).
- [ ] `smart_routing`: helper puro `appendCapabilitySelections*(selections, catalog, query, providerIds)` recebe ids **ordenados por id** e consulta **por provider** (`ModelQuery.provider`), nunca com provider vazio nem iterando `Table.entries`; `smartRouteSelections` usa os ids de `providerDescriptors()` ordenados e acrescenta os capazes **depois** da ordem atual. Nada reordena.
- [ ] Efeito real: NVIDIA entra na lista de imagem porque `supportsImages=true`. Contexto de produção é 0 nos três, então o ramo de contexto longo **não muda produção**; um provider sintético (`contextWindow=200_000`) no teste prova o mecanismo e **falha se o limite for ignorado**. Provider com `supportsImages=false` não entra.
- [ ] Propagação do transporte US-009: estender `tests/app/t_provider_breadth_surface.nim` (criado na US-001) provando que `doctor`, `setup_wizard`, TUI e a lista de custo de `src/donkey.nim` mostram os três ids sem lista local; se algum ainda hardcodar, **pare e escale** ao dono do transporte, não edite o arquivo dele.
- [ ] `tests/domain/providers/t_model_limits_catalog.nim` e `tests/core/providers/t_catalog_limits.nim`; testes atuais de smart routing/catálogo sem edição.

### US-006: Documentar e fechar a missão

**Descrição:** a próxima pessoa entende adapter, breadth, limites e o buraco de OAuth.

- [ ] `docs/topics/providers.md`: “Adapter compat” (perfil → `CompatAdapter` → `openai_pure`), “Breadth” com a tabela dos três, “Limites” com `sourceRef` e 0 = não afirmar, e “OAuth device-code: TODO de longo prazo” copiando §6.1; `docs/index.md` lista o tópico.
- [ ] `rg -n "toJson|buildBody|newHttpClient" src/donkey/domain/providers/profile_{nvidia,alibaba,fireworks}.nim` vazio; `rg -n "HermesAgent" src/donkey` vazio; commit registra que OAuth Copilot/Codex e Bedrock/Vertex/Azure seguem fora e que o placar não é recalculado.

### 6.1 OAuth device-code — TODO de longo prazo

**Status: DEFERIDO por decisão do mantenedor (18/11/2026). Nenhuma história implementa OAuth; providers são API-key.**

`nous` é o único provider com `auth_type="oauth_device_code"` (`providers.py:31`, `auth.py:174-177`): client público `hermes-cli` (`auth_constants.py:60`), portal `https://portal.nousresearch.com`, inference `https://inference-api.nousresearch.com/v1`, escopo `inference:invoke` (`auth_constants.py:54-66`). Fluxo verificado: `POST {portal}/api/oauth/device/code` (form `client_id`, `scope`) devolve `device_code`/`user_code`/`verification_uri(_complete)`/`expires_in`/`interval` (`auth_device_flow.py:270-285`); poll em `POST {portal}/api/oauth/token` com grant device-code (`auth_device_flow.py:409-438`); refresh no mesmo endpoint com `grant_type=refresh_token` e header `x-nous-refresh-token` (`auth_nous.py:700-710`). O pool serializa refresh single-use (`credential_pool.py:1479-1508`).

**Bloqueio preciso:** o fluxo não precisa de segredo do usuário, mas precisa de **identidade de cliente**. `hermes-cli` é do Hermes; usá-lo personifica outro cliente. Alternativas: (a) client público do Donkey registrado no Nous Portal (device code + `inference:invoke`), com `client_id`/portal/inference documentados; ou (b) autorização escrita para reutilizar `hermes-cli`. Sem uma delas, **zero código OAuth**; o item fica no TODO de longo prazo. Quando houver identidade de cliente, um PRD próprio entrega `domain/providers/oauth_device_pure.nim` (máquina de estados, clock injetado), `ports/oauth.nim`, adapter HTTP e store 0600, com testes por transporte falso.

## 7. Requisitos funcionais

- **FR-1:** Provider novo = 1 linha no descritor + 1 perfil puro + 1 linha aditiva na conformidade + fiação; **nunca** adapter por provider.
- **FR-2:** `CompatAdapter` é o único consumidor de `profile.extraHeaders`/`profile.endpoint`; perfil é dado, não código.
- **FR-3:** `modelLimits` é puro e desconhecido é 0/false; ausência nunca vira promessa de contexto, visão ou tools.
- **FR-4:** Roteamento lê capacidades do catálogo em ordem determinística (ids ordenados), sem reordenar os providers atuais.
- **FR-5:** Nenhuma rede nos testes; `Result`, não exceção, nas bordas.

## 8. Não-objetivos

Enriquecimento por `/models` ao vivo; fetch de models.dev; `qwen-oauth`/`minimax-oauth`; OAuth Copilot/Codex; Bedrock/Vertex/Azure nativos; mudar a forma de `ProviderCaps`; campo de visão em `ProviderCaps`; consumir `baseUrlEnv`; UI/dashboard novos; streaming com `delta.reasoning`; cooldown/pool/smart routing além da US-005.

## 9. Considerações técnicas

- O adapter genérico é `ProviderPort` de verdade: `buildBody`, `complete`, `makeStreamFn`, `caps`; `runtime_builder` só o constrói por perfil. Nada de `case` de provider dentro dele.
- `CompatProfile` carrega JsonNodes: o adapter guarda `profileFn` e reconstrói o perfil dentro do worker/stream, como o OpenRouter; nada de JsonNode no closure que atravessa thread.
- `include_reasoning` é extensão do Donkey; `includeReasoningField=false` só evita enviá-la e **não** descreve comportamento de provider.
- `ProviderAvailability` é objeto fixo: cada provider exige campo, `isAvailable`, `detectProviderAvailability` e `availableProviderNames`; sem isso o roteamento nunca o escolhe.
- O `case` de `runtime_builder` tem fallback Zhipu; o teste do bundle (`streamFn != nil`) existe para pegá-lo.
- `ProviderCaps` só ganha `maxContextTokens` via `modelLimits`; visão/tools vivem no catálogo. Não mude a forma. Migração provider a provider, um commit por história.

## 10. Métricas de sucesso

- `newCompatAdapter` usado pelos três providers; zero `newNvidiaAdapter`-style com HTTP próprio e zero `adapters/provider/{nvidia,alibaba,fireworks}.nim`.
- NVIDIA: imagem preservada e `reasoning_content` não-streaming parseado; SSE de conteúdo coberto.
- Limite desconhecido é sempre 0/false; teste sintético falha se o roteamento ignorar contexto/visão; ordem atual byte-idêntica.
- Suíte verde (baseline do dia do start), `check_boundaries.sh` exit 0, nenhum import novo de `adapters/` em `domain/`/`core/`.

## 11. Questões em aberto

- **OAuth:** client-id do Donkey ou autorização para `hermes-cli` (§6.1); até lá, bloqueado.
- **NVIDIA:** `X-BILLING-INVOKE-ORIGIN: Donkey` é aceito ou precisa de registro, e deve ser omitido em NIM local? Contexto do Nemotron não está no Hermes (fica 0).
- **Alibaba:** default `qwen3.8-max` ou o exemplo `qwen3.5-plus`? Visão não verificada; `preserve_thinking` só com replay de `reasoning`.
- **Fireworks:** `HTTP-Referer`/`X-Title`/`User-Agent` ideais? `kimi-k2p6` é escolha do Donkey; falta campo de esforço para mapear `reasoning_effort` além de `"none"`.
- **Streaming:** `parseOpenAISseLine` ignora `delta.reasoning`; acumular reasoning em SSE fica fora desta missão e precisa de história própria.
[/PRD]
