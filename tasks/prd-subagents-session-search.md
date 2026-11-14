[PRD]
# PRD: P2.1 — Subagentes e session search

## 1. Visão geral

O Donkey já tem sessões, memória em arquivos, ledger, sandbox, approval gate e jobs paralelos simples (`task`/`await`/`cancel_job`). Falta transformar isso em **delegação real**: subagentes com contexto, ferramentas, workspace e orçamento próprios, e uma busca segura no histórico de sessões.

Este PRD entrega dois blocos:

1. `session_search` — busca lexical/semântica no histórico do próprio usuário, com isolamento e limites.
2. Subagente — uma sessão filha com escopo, ferramentas, budget, cancelamento, approval herdado e auditoria.

O objetivo não é copiar o Kanban/rooms do Hermes. É criar a fundação confiável para delegação, mantendo o estilo “boring” do Donkey: limites explícitos, falha fechada e nenhum bypass de approval.

## 2. Objetivos

- Permitir que o agente encontre decisões, preferências e conversas passadas sem carregar todo o histórico no contexto.
- Permitir que o agente delegue uma tarefa a um filho isolado, com resultado estruturado.
- Impedir que o subagente acesse outro usuário, outro paddock, approval ou rede sem política.
- Provar cancelamento, timeout, órfãos, concorrência e isolamento com testes.
- Manter o caminho síncrono/assíncrono atual do orchestrator e o contrato `ToolRuntimePort`.

## 3. Quality Gates

Toda história deve passar:

- `bash scripts/check_boundaries.sh`
- `nimble build -y`
- `JOBS=6 bash scripts/run_tests.sh`
- `bash scripts/run_stress_tests.sh` quando tocar concorrência/tempo
- `coderabbit review --agent --base master`
- CI do GitHub Actions verde

Critérios adicionais:

- testes de isolamento entre usuários e entre paddocks;
- nenhum teste depende de rede/browser/Docker real;
- budgets e timeouts têm teste de borda;
- cancelamento não deixa subagente órfão;
- nenhuma aprovação é feita pelo subagente em nome do usuário.

## 4. Não-objetivos

- Kanban, rooms, relay multiagente e UI de orquestração.
- Subagente com acesso irrestrito ao filesystem ou à rede.
- Vetorização/embeddings obrigatórios para `session_search`; busca lexical deve funcionar sem provider.
- Substituir o `task` atual de uma vez; ele pode coexistir como job simples.
- Deletar ou reescrever histórico de sessões.

## 5. Histórias de usuário

### US-001: Política pura de busca de sessões

**Descrição:** Como mantenedor, quero que tokenização, score, snippet e corte de resultados sejam puros e testáveis.

**Critérios de aceite:**
- [ ] `domain/memory/session_search_pure.nim` não importa I/O, adapter ou chronos.
- [ ] Busca é case-insensitive, com AND de termos e fallback para OR.
- [ ] Score combina ocorrências, frase exata, papel da mensagem e recência.
- [ ] Snippet é limitado e não corta UTF-8 no meio.
- [ ] Testes cobrem query vazia, termos repetidos, acentos, emoji e limite zero.

### US-002: Leitura de transcripts por usuário

**Descrição:** Como operador, quero buscar apenas nos arquivos do paddock do usuário, sem cruzar identidades.

**Critérios de aceite:**
- [ ] Adapter lê `{paddock}/sessions/*.jsonl` e `MEMORY.md`.
- [ ] JSONL inválido é ignorado sem derrubar a busca.
- [ ] Sessões/arquivos acima do cap são ignorados de forma determinística.
- [ ] Resultados carregam `sessionId`, `kind`, `role`, `timestampMs`, `score` e `snippet`.
- [ ] `searchSessions` no `MemoryRuntimePort` é opcional (`nil` = backend sem suporte).
- [ ] Teste com dois usuários prova que A não vê B.

### US-003: Tool `session_search`

**Descrição:** Como usuário, quero perguntar “o que decidimos sobre X?” e receber trechos do meu histórico.

**Critérios de aceite:**
- [ ] Tool nativa `session_search` com `query`, `limit` e `include_memory`.
- [ ] `limit` default 10, clamp `1..50`.
- [ ] Resultado em texto/JSON estável com sessão, papel, score e snippet.
- [ ] Query vazia retorna erro de uso.
- [ ] Tool é read-only e não passa pelo approval gate.
- [ ] Teste de integração via `executeNativeTool`.

### US-004: Runtime de subagente

**Descrição:** Como agente pai, quero delegar uma tarefa a um filho isolado e receber o resultado.

**Critérios de aceite:**
- [ ] `spawn_subagent` cria uma sessão filha com ID próprio e paddock/worktree isolado.
- [ ] Filho herda provider/modelo, mas não herda histórico inteiro; recebe só a tarefa e contexto explícito.
- [ ] Filho tem lista de tools permitidas configurável; por default, tools de leitura e `session_search`, sem `bash`/`execute_code`/escrita.
- [ ] Filho não pode criar outro subagente (profundidade máxima 1).
- [ ] Resultado inclui `subagent_id`, `status`, `text`, `error`, `tool_calls`, `duration_ms` e `cost` quando disponível.
- [ ] Filho é cancelável por `cancel_subagent` e por timeout.
- [ ] Teste com filho tentando escrever fora do paddock falha.

### US-005: Approval, rede e orçamento herdados

**Descrição:** Como operador, quero que o subagente respeite as mesmas políticas do pai.

**Critérios de aceite:**
- [ ] Filho usa o mesmo `ApprovalService`; pedidos de approval vão ao usuário, não ao pai.
- [ ] Filho não pode aprovar nem negar pedidos.
- [ ] Política de rede/URL do filho é a mesma do pai.
- [ ] Budget de tokens/tempo/tool calls é configurável e falha fechado ao estourar.
- [ ] Filho não herda segredos que não estejam no seu escopo.

### US-006: Observabilidade e cancelamento

**Descrição:** Como operador, quero ver e cancelar subagentes sem deixar processos/estado órfãos.

**Critérios de aceite:**
- [ ] `list_subagents` mostra id, status, idade, budget usado e última atividade.
- [ ] `cancel_subagent` é idempotente e retorna em < 2s.
- [ ] Shutdown do daemon cancela todos os filhos.
- [ ] Nenhum worktree/paddock temporário fica para trás após falha/cancelamento.
- [ ] Eventos de subagente aparecem no log estruturado/IPC.
- [ ] Testes de concorrência com 8+ filhos e cancelamento no meio.

## 6. Sequência de entrega

1. PR A — US-001..US-003 (`session_search`).
2. PR B — US-004..US-005 (runtime + políticas).
3. PR C — US-006 (observabilidade/cancelamento) se não couber no PR B.

Cada PR deve ser mergeável sozinho, com CI verde e sem dependência do outro.

## 7. Restrições de desenho

- O `SessionEntry` do filho precisa de alocação estável (`ref object` mantido pelo job pai), porque `runOrchestrator` recebe `ptr SessionEntry`.
- O outbox do filho é drenado pelo pai; o filho não escreve direto no canal do usuário.
- O filho recebe uma cópia filtrada dos `ToolRuntimePort`/`ToolDescription`; tools de escrita, `bash`, `execute_code` e `spawn_subagent` ficam fora do default.
- O approval service é o global do daemon; o filho não pode decidir. Pedidos vão ao usuário com o nome do filho no resumo.
- Budget: envolver `CompleteFn` e o dispatch de tools com contadores de tokens/tempo/tool calls; ao estourar, cancelar o filho e devolver erro tipado.
- Cancelamento: `cancel_subagent` envia `newCancelMsg` para o inbox do filho, aguarda o future com timeout e remove o diretório temporário.
- O paddock do filho é um subdiretório `{paddock}/subagents/{id}` com `0700`; o filho não recebe o paddock do pai no `NativeCtx`.
- `session_search` do filho continua escopado ao usuário, mas não vê o histórico do pai além do que for passado no contexto explícito.
