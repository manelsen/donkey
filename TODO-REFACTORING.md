# TODO — Refatoração Pós-Estrutural

Gerado após auditoria de qualidade (abril/2026). 12 alvos priorizados por risco.

---

## Threads Paralelizáveis

### Onda 1 — Pequeno, independente, rápido (rodar tudo em paralelo)

| Thread | Alvos | Escopo | Branch sugerida |
|--------|-------|--------|-----------------|
| **W1-A** | #1 + parte de #10 | `app/heartbeat.nim` | `w1-a-heartbeat-silent` |
| **W1-B** | #2 + #3 | `app/multigraph_runtime.nim`, `adapters/memory/postgres_memory.nim` | `w1-b-boundary-age-silent` |
| **W1-C** | #4 + #12 | `tests/` | `w1-c-test-isolation` |
| **W1-D** | #11 | `adapters/channel/common_runtime.nim` | `w1-d-modelmenu-catalog` |

### Onda 2 — Extrações grandes (após Onda 1 merged)

| Thread | Alvos | Escopo | Branch sugerida |
|--------|-------|--------|-----------------|
| **W2-A** | #5 + #8 + #9 | `app/orchestrator.nim` | `w2-a-orchestrator-split` |
| **W2-B** | #6 | `app/native_tools.nim` | `w2-b-native-tools-split` |
| **W2-C** | #7 | `adapters/channel/*.nim`, `app/*.nim` | `w2-c-global-state` |

### Onda 3 — Limpeza final (após Onda 2)

| Thread | Alvos | Escopo | Branch sugerida |
|--------|-------|--------|-----------------|
| **W3-A** | #10 (restante) | `adapters/`, `app/` | `w3a-stderr-to-logger` |

---

## #1 🔴 — Eliminar `except CatchableError: discard` em heartbeat

**Arquivo:** `src/donkey/app/heartbeat.nim` (linhas 71, 94)

**Problema:** `runAllTasks` e `runCommitmentReview` engolem erros completamente. Tarefas de accountability, contemplação e reminder param sem registro. O agente para de seguir compromissos e ninguém vê.

**Critérios de aceite:**
- [ ] `runAllTasks` loga `error` com task name e exception message ao falhar
- [ ] `runCommitmentReview` loga `error` com user id e reason ao falhar
- [ ] Teste unitário simula falha de task e verifica log
- [ ] `nim c src/donkey.nim` passa
- [ ] `bash scripts/run_tests.sh` não introduz novas falhas

---

## #2 🔴 — Eliminar `except CatchableError: discard` em operações do grafo AGE

**Arquivo:** `src/donkey/adapters/memory/postgres_memory.nim` (linhas 201, 224, 279)

**Problema:** `saveUserMd`, `appendMemory`, `deleteUser` falham silenciosamente no grafo PostgreSQL enquanto o Markdown persiste. Divergência de dados silenciosa — o agente usa dados desatualizados.

**Critérios de aceite:**
- [ ] `saveUserMd` loga `error` ao falhar AGE MERGE de perfil
- [ ] `appendMemory` loga `error` ao falhar AGE MERGE de memória
- [ ] `deleteUser` loga `error` ao falhar AGE DELETE
- [ ] Teste simula falha de conexão e verifica log
- [ ] `nim c -d:withPostgres src/donkey.nim` passa
- [ ] `bash scripts/run_tests.sh` não introduz novas falhas

---

## #5 🟡 — Extrair orchestrator.nim (1781 linhas)

**Arquivo:** `src/donkey/app/orchestrator.nim`

**Problema:** Concentra onboarding runtime, tool loop, streaming runtime, prompt building, typing loop em um arquivo só. Qualquer mudança tem risco de regressão cruzada.

**Alvos filhos: #8 (jobs fantasmas), #9 (paddock divergente)**

**Critérios de aceite:**
- [ ] Extrair `OnboardingRuntime` para módulo próprio (onboarding, free conversation, profile capture)
- [ ] Extrair `ToolLoop` para módulo próprio (tool call dispatch, result handling, batch processing)
- [ ] Extrair `StreamingRuntime` para módulo próprio (token streaming, partial edit)
- [ ] Extrair `PromptBuilding` para módulo próprio (system prompt, context assembly)
- [ ] Remover ou documentar `CancelJob`/`Await`/`SubmitResult` (#8) — ou implementar ou remover superfície
- [ ] Unificar paddock path: orchestrator usa `cfg.paddocks` em vez de `~/.donkey/paddocks` (#9)
- [ ] `orchestrator.nim` reduz para < 600 linhas
- [ ] `nim c src/donkey.nim` passa
- [ ] `bash scripts/run_tests.sh` não introduz novas falhas
- [ ] Testes existentes de orchestrator continuam passando

---

## #3 🔴 — Resolver boundary violation em multigraph_runtime.nim

**Arquivo:** `src/donkey/app/multigraph_runtime.nim` (linhas 12-17)

**Problema:** Importa 6 adapters diretamente (`openrouter_embed`, `zai_rerank`, `minimax_rerank`, `openrouter_rerank`, `md_file`, `magma_memory_adapter`). Viola regra "app must not import adapters". Quebra `check_boundaries.sh`.

**Critérios de aceite:**
- [ ] `multigraph_runtime.nim` não importa adapters diretamente
- [ ] Embedding e reranking injetados via ports ou factory
- [ ] `bash scripts/check_boundaries.sh` passa
- [ ] `tests/architecture/t_boundaries.nim` passa
- [ ] `nim c src/donkey.nim` passa
- [ ] `bash scripts/run_tests.sh` não introduz novas falhas

---

## #4 🟡 — Corrigir test isolation deficiency

**Arquivos:** `tests/app/t_error_policy.nim`, `tests/core/t_telegram_format.nim`, `tests/core/t_tool_loop.nim`, `tests/domain/providers/t_gemini_pure.nim`, `tests/infra/sandbox/t_wasm.nim`, `tests/adapters/channel/t_telegram_runtime.nim`

**Problema:** 6 de 7 testes falham no harness mas passam isoladamente. Estado global compartilhado mascara bugs reais.

**Critérios de aceite:**
- [ ] `bash scripts/run_tests.sh` passa todos os 7 testes sem falha
- [ ] Cada teste isola temp dirs, limpa singletons entre execuções
- [ ] Nenhum teste depende de ordem de execução
- [ ] `bash scripts/run_tests.sh` resultado final: 0 novas falhas

---

## #6 🟡 — Extrair native_tools.nim (1472 linhas)

**Arquivo:** `src/donkey/app/native_tools.nim`

**Problema:** 14+ tools em um único arquivo. `except CatchableError: discard` em `walkFind`, `grepFile`, `grepDir`. Difícil de testar, difícil de evoluir.

**Critérios de aceite:**
- [ ] Cada tool nativa (ou grupo coeso) em módulo próprio sob `app/tools/`
- [ ] `walkFind`, `grepFile`, `grepDir` substituem `discard` por `log.warn`
- [ ] `native_tools.nim` reduz para < 200 linhas (apenas dispatch + registro)
- [ ] Testes unitários por tool
- [ ] `nim c src/donkey.nim` passa
- [ ] `bash scripts/run_tests.sh` não introduz novas falhas

---

## #7 🟡 — Auditar e proteger 28 variáveis globais

**Arquivos:** `core/reliability.nim`, `core/log.nim`, `adapters/channel/whatsapp.nim`, `wecom.nim`, `discord.nim`, `slack.nim`, `matrix.nim`, `dingtalk.nim`, `qq_official.nim`, `qq_webhook.nim`, `feishu.nim`

**Problema:** `gDiscordPending: seq` e `gMxTxnSeq: int` sem lock — risco de corrupção em runtime concorrente. 28 variáveis globais com estado mutável.

**Critérios de aceite:**
- [ ] `gDiscordPending` protegido por lock ou substituído por AsyncQueue
- [ ] `gMxTxnSeq` protegido por lock atômico
- [ ] Cada variável global documentada com justificativa ou migrada para injeção de dependência
- [ ] Teste de concorrência para Discord e Matrix (se aplicável)
- [ ] `nim c src/donkey.nim` passa
- [ ] `bash scripts/run_tests.sh` não introduz novas falhas

---

## #8 🟡 (sub-task de #5) — Jobs/subtasks fantasmas

**Arquivo:** `src/donkey/app/orchestrator.nim`

**Problema:** `CancelJob`, `Await`, `SubmitResult` operam sobre `state.jobs` que nunca é populado. `TaskToolName` é síncrono mas a descrição sugere paralelismo. Superfície morta que confunde.

**Critérios de aceite:**
- [ ] Ou implementar jobs async reais, ou remover `CancelJob`/`Await`/`SubmitResult` da superfície de commands
- [ ] Documentar decisão no código (por que remover ou por que implementar)
- [ ] `nim c src/donkey.nim` passa

---

## #9 🟡 (sub-task de #5) — Paddock path divergente

**Arquivo:** `src/donkey/app/orchestrator.nim`

**Problema:** Orchestrador hardcodea `~/.donkey/paddocks`, adapter usa `cfg.paddocks`. Se o config apontar outro lugar, o orchestrator lê do lugar errado.

**Critérios de aceite:**
- [ ] Orchestrator usa `cfg.paddocks` em vez de path hardcodeado
- [ ] Teste verifica que paddock path do orchestrator = paddock path do adapter
- [ ] `nim c src/donkey.nim` passa

---

## #10 🟢 — Migrar 16× `stderr.writeLine` para logger estruturado

**Arquivos:** `adapters/memory/postgres_memory.nim`, `adapters/channel/wechat.nim`, `qq.nim`, `wecom.nim`, `app/http_gateway.nim`, `adapters/embedding/openrouter_embed.nim` (o restante em `donkey.nim` são warnings de startup — aceitáveis)

**Problema:** Formato ad-hoc (`[WRN] ...`) não é parseável por sistemas de observabilidade.

**Critérios de aceite:**
- [ ] `stderr.writeLine` substituído por `log.warn()` ou `log.error()` onde Logger está disponível
- [ ] Formato consistente com política de erro (`tasks/error-policy.md`)
- [ ] `nim c src/donkey.nim` passa

---

## #11 🟢 — Derivar ModelMenu do ProviderCatalog

**Arquivo:** `src/donkey/adapters/channel/common_runtime.nim` (linhas 25-35)

**Problema:** Lista de modelos por provider hardcoded precisa de atualização manual. O ProviderCatalog já existe e é a fonte de verdade.

**Critérios de aceite:**
- [ ] `ModelMenu` gerado dinamicamente a partir do ProviderCatalog
- [ ] Menu reflete modelos registrados, não lista estática
- [ ] `nim c src/donkey.nim` passa
- [ ] `bash scripts/run_tests.sh` não introduz novas falhas

---

## #12 🟢 — Corrigir teste `t_more_tools.nim`

**Arquivo:** `tests/domain/t_more_tools.nim` (linha ~101)

**Problema:** Teste falha consistentemente porque descrição de `manage_skills` mudou e não contém mais a string esperada ("next message").

**Critérios de aceite:**
- [ ] Assertion atualizada ou descrição da tool corrigida
- [ ] `tests/domain/t_more_tools.nim` passa isoladamente e no harness
- [ ] `bash scripts/run_tests.sh` — este teste específico passa

---

## Matriz de Dependências

```
Onda 1 (paralelo total):
  W1-A: #1 ──────────────────────────────────────────→
  W1-B: #2 ──────────────────────────────────────────→
        #3 ──────────────────────────────────────────→
  W1-C: #4 ──────────────────────────────────────────→
        #12 ─────────────────────────────────────────→
  W1-D: #11 ─────────────────────────────────────────→

Onda 2 (após Onda 1):
  W2-A: #5 ──→ inclui #8, #9 ──────────────────────→
  W2-B: #6 ──────────────────────────────────────────→
  W2-C: #7 ──────────────────────────────────────────→

Onda 3 (após Onda 2):
  W3-A: #10 (restante) ─────────────────────────────→
```
