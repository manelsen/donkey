# Roadmap de execução — 7 missões (pós-V4)

> Fontes: `COBERTURA_HERMES_VS_DONKEY_V4.md` §6 e os PRDs em `tasks/`.
> Baseline: suíte completa do `master` no dia do start (a V4 registrou **242 passed, 0 failed** em `42b579a9`).
> `tasks/reviews/*.md` não existia quando este roteiro foi escrito.
> Nota: nenhum PRD cobre OAuth/breadth de providers (V4 §6, item 4); a missão 1 é refactor de arquitetura e não move o placar.

## 1. Ordem das missões

| # | Missão | PRD | Porquê (uma linha) |
|---:|---|---|---|
| 1 | Transporte de provider | `tasks/prd-provider-transport.md` | Já é a missão ativa, não muda comportamento e libera `session_bootstrap.nim`/`domain/providers/*`, disputados pela missão 2. |
| 2 | Ferramentas | `tasks/prd-ferramentas.md` | Melhor peso×distância (18% × 35) e consome o arquivo liberado pela 1. |
| 3 | Interfaces | `tasks/prd-interfaces.md` | 2º melhor retorno (4,7 pts) com arquivos quase disjuntos de ferramentas. |
| 4 | Multiagente | `tasks/prd-multiagente.md` | Maior distância absoluta (52); disputa `native_tools.nim` com ferramentas US-006, então vem depois. |
| 5 | Canais | `tasks/prd-canais.md` | Peso alto (18%) mas distância curta (20); mexe em `ChannelKind` e `src/donkey.nim`. |
| 6 | Automação | `tasks/prd-automacao.md` | Distância 44; toca `orchestrator.nim`, que precisa estar estável antes da missão 7. |
| 7 | Durabilidade | `tasks/prd-durabilidade.md` | Menor potencial (1,3) e o diário do turno deve ser o último a entrar no `orchestrator.nim`. |

## 2. Dependências entre PRDs (código e arquivos)

- **ferramentas → provider-transport:** ferramentas US-003 e US-006 usam `app/session_bootstrap.nim` (`buildCompleteFn`, catálogo de tools) e `domain/providers/media_pure.nim`, reescritos por provider US-001/US-002.
- **interfaces → provider-transport:** `descriptors.nim`/`providerDescriptor` alimentam `/api/providers` (interfaces US-005); interfaces não edita `compat.nim`/`openai_pure.nim`.
- **multiagente → ferramentas:** multiagente US-004 reusa `app/native_tools.nim`, `core/tooling/native_tool_dispatch.nim` e `nativeSessionTools()` de ferramentas US-006.
- **durabilidade → interfaces/canais:** `OutboundMessage` ganha campos em interfaces US-003/US-004 (`inputTokens`, `toolCall`) e durabilidade US-005 (`deliveryId`); a ordem 3 → 5 → 7 evita rebase.
- **durabilidade → automação:** automação US-005 cria `tkSchedule` em `domain/agent_message.nim` e ensina `orchestrator.nim`; durabilidade US-004 deve tratar `tkSchedule` como `tkHeartbeat`.
- **automação → durabilidade:** automação US-003 espelha `adapters/state/runtime_store.nim` sem editá-lo; durabilidade US-002 extrai `durable_file.nim` — sem conflito se US-002 rodar depois da 6.
- **canais → nada:** `ckLine` é aditivo em `core/types.nim`; o portão é o build quebrar os `case` exaustivos.

## 3. Paralelização

Concorrente (arquivos disjuntos):
- ferramentas US-001/US-002/US-004 (`media_pure`, `inbound_media`, `prompt_building`, `adapters/memory`) ∥ interfaces US-001/US-002 (`domain/gateway/*`, `chat_bridge`).
- multiagente US-001/US-002 (`domain/fanout_pure`) ∥ canais US-001/US-002 (`core/types` com `ckLine`, `domain/channels/line_*`).
- automação US-001/US-002 (`domain/automation/*`) ∥ durabilidade US-001 (`domain/session/turn_journal_pure`) e durabilidade US-003/US-008.
- Dentro de cada missão: pesquisa e redação de testes em paralelo; implementação só com arquivos disjuntos; suíte completa, stress e commits sempre na sessão principal.

Escritores únicos (serializam histórias):
| Arquivo | Dono por vez (ordem) |
|---|---|
| `app/session_bootstrap.nim` | provider US-001 → ferramentas US-003 → ferramentas US-006 → multiagente US-004 |
| `adapters/state/runtime_store.nim` | durabilidade US-002 (extrai `durable_file.nim`); mais ninguém edita |
| `app/orchestrator.nim` | automação US-005 → durabilidade US-004 → US-005 → US-006 |
| `core/types.nim` (`ChannelKind`) | canais US-001; ferramentas US-005 só adiciona `cfSendVoice` em `ports/channel_capability.nim` |
| `app/native_tools.nim` + `core/tooling/native_tool_dispatch.nim` | ferramentas US-006 → multiagente US-004 |
| `docs/` | só a história de fechamento da missão corrente (provider US-010, ferramentas US-007, interfaces US-007, multiagente US-007, canais US-007, automação US-008, durabilidade US-008) |
| `src/donkey.nim` + `domain/message.nim` | portões extras: interfaces US-003/US-004, canais US-005, automação US-006, durabilidade US-007 |

## 4. Definition of done e gate de cada missão

Gate padrão de toda história: `bash scripts/check_boundaries.sh` + `nimble build -y` + `JOBS=6 bash scripts/run_tests.sh` + `git diff --check`.
Abaixo, o teste que **prova** a missão (rodado sozinho com `bash scripts/run_tests.sh <arquivo>`).

| # | DoD | Gate que prova |
|---:|---|---|
| 1 | Descritor é fonte única de env/modelo/base URL; zero `toJson`/`buildBody` OpenAI-shaped; `quirks.nim` removido; comportamento idêntico. | `t_descriptors.nim` + `t_compat_conformance.nim` (exceção declarada: remoção de `t_quirks.nim`, US-007). |
| 2 | Foto inbound = 1 chamada e 0 `inspect_image`; transcript sem `data:image`; voz no Telegram com fallback de texto. | `tests/app/t_inline_image_turn.nim`, `t_image_fallback.nim`, `t_voice_reply.nim`, `tests/domain/channels/t_telegram_upload_pure.nim`; `rg base64 src/donkey/adapters/memory` → 0. |
| 3 | `/v1/chat/completions` roda o turno real (tools/memória/sessão) + SSE; dashboard lê sessões/providers e encerra sessão. | `tests/app/t_agent_chat.nim`, `t_agent_chat_stream.nim`, `t_dashboard_api.nim`, `t_dashboard_action.nim`; `rg "chatReply\|not the agent loop"` vazio (exceção declarada: remoção de `t_openai_compat.nim`, US-003). |
| 4 | 3 filhos iniciam antes da 1ª resposta (barreira), agregado ordenado, 0 paddock órfão, tokens somados. | `tests/domain/t_fanout_pure.nim`, `tests/app/t_subagent_fanout.nim`, `t_subagent_fanout_stop.nim` + `bash scripts/run_stress_tests.sh`. |
| 5 | LINE inbound/outbound ponta a ponta; ingress compartilhado provado pelo DingTalk; receiver antigo intocado. | `t_line_pure.nim`, `t_line_policy.nim`, `t_webhook_ingress.nim`, `t_line_webhook.nim`, `tests/channel/t_line.nim`, `t_line_runtime.nim`. |
| 6 | Schedule sobrevive a restart; 1 ocorrência = 1 run; `ctl schedule list/show` sem daemon; store corrompido não derruba o daemon. | `t_schedule_pure.nim`, `t_schedule_due.nim`, `tests/state/t_schedule_store.nim`, `t_scheduler_runtime.nim`, `t_scheduler_wiring.nim`, `t_ctl_schedule.nim`. |
| 7 | 11/11 crash points sem duplicar resposta ou memória; relatório de recuperação em todo startup. | `t_turn_journal_pure.nim`, `tests/state/t_turn_journal.nim`, `t_turn_recovery.nim`, `t_turn_recovery_startup.nim`, `t_memory_idempotency.nim`. |

## 5. Regra de baseline

- Baseline = **suíte completa** do `master` no dia do start; registrar a contagem no commit de abertura e nunca reescrevê-la.
- Nenhum teste existente editado; bloco novo só onde o PRD autoriza (durabilidade US-005 em `t_outbound_runtime.nim`). Remoções declaradas: `t_openai_compat.nim` (interfaces US-003) e `t_quirks.nim` (provider US-007) — não são "edição para acomodar".
- TDD: primeiro sinal é o teste novo sozinho **falhando**; o vermelho → verde entra no corpo do commit.
- Cada missão termina com a suíte completa verde e `check_boundaries.sh` exit 0 antes da próxima abrir.

## 6. Stop rules

1. Não abrir missão nem história com o gate vermelho.
2. Não paralelizar missão/história no mesmo arquivo de escritor único.
3. Worktree sujo no arquivo que você possui → pare e registre; nunca `stash`, `reset` ou `checkout` sobre trabalho alheio.
4. Não rodar `run_tests.sh` completo nem commits em paralelo (binários colidem).
5. Teste existente precisou mudar → pare e escale: o comportamento mudou, não o teste.
6. Precisou editar arquivo de outro dono/PRD → combine na sessão principal antes.

## Review gate (18/11/2026)

- Todo PRD passa por uma revisão independente em `tasks/reviews/prd-*.md`
  antes de entrar na fila.
- `PASS` → executa; `PASS WITH FIXES` → o autor corrige o PRD antes de
  executar; `BLOCK` → não executa até fechar os itens.
- O PRD de transporte de providers está em execução; as auditorias das
  migrações são consultivas e estão sendo aplicadas como commits de follow-up.
- Falta o PRD da prioridade **Providers** da V4 (OAuth/breadth); está em
  escrita. Sem ele, a missão de transporte não conta como cobertura de
  Providers.

## Review status (18/11/2026)

| PRD | Revisão | Estado |
|---|---|---|
| Provider transport | auditorias das 3 migrações + reforço de testes | em execução (US-007/008/009 + follow-ups) |
| Ferramentas | BLOCK → corrigido | re-revisão em curso |
| Interfaces | PASS WITH FIXES | corrigido |
| Multiagente | em revisão | aguardando |
| Canais | PASS WITH FIXES | autor corrigindo |
| Automação | PASS WITH FIXES | corrigido |
| Durabilidade | BLOCK | autor corrigindo |
| Providers (V4) | BLOCK | correção em curso |

Regra: `BLOCK` não executa; `PASS WITH FIXES` corrige o PRD antes de abrir a
missão; `PASS` entra na fila.

## OAuth — decisão de 18/11/2026

OAuth device-code está **fora de escopo por decisão do mantenedor**. Os
providers do Donkey são API-key; o fluxo fica como TODO de longo prazo e não
bloqueia nenhuma missão. Registro para o futuro: o Hermes tem device code no
`nous`, mas o client id público é do Hermes (`hermes-cli`); o Donkey precisaria
de um client id próprio registrado ou de autorização escrita para reutilizá-lo.

## 5. Estado em 18/11/2026 (pós-onda de fundações)

Ondas entregues: PR #53 (transporte de provider), PR #54 (ferramentas US-001..007),
PR #56 (fundações: Interfaces US-001/002, Canais US-000..002, Providers
US-001..003 + surface, Multiagente US-001..003, Automação US-001/002,
Durabilidade US-001/002, hardening de upload, cron) e a onda 2 (N3) em curso.

| Missão | Entregue | Falta para N3 |
|---|---|---|
| Transporte de provider | completo | — |
| Ferramentas | US-001..007 + hardening + marcador por álbum + cap antes do merge + retry por turno (streaming incluso) + confinamento ao paddock + `isImageRejection` único + `inspect_image` na política + voz com `replyTo` | TTS pelo store port, GC de anexos |
| Interfaces | US-001..004 (contrato, endpoint, SSE, dashboard) + docs | token por registro no `ChatBridge`; US-005 fechamento |
| Multiagente | US-001..003 (fan-out + supervisor) | US-004 (rooms/relay) |
| Canais | US-000..006 (enum, parser, política, ingress, adapter, rota, runtime) + docs | US-007 (prova de não-duplicação e rollout) |
| Automação | US-001/002 (puro) + runtime + `enqueueScheduledTask`/`tkSchedule` + store de watermark | store com spec completo, `ctl schedule` (US-007), tick no daemon |
| Durabilidade | US-001/002 (FSM + store) | US-003+ (recuperação no caminho do turno) |
| Providers | US-001..004 + availability/routing/doctor/setup; catálogo com limites desconhecidos | US-005 (limites verificados), OAuth (TODO de longo prazo) |

Testes-gate que **não** existem ainda com os nomes deste roteiro:
`t_agent_chat_stream.nim` (SSE vive em `t_agent_chat.nim`),
`t_subagent_fanout.nim`/`t_subagent_fanout_stop.nim` (viram `t_fanout_plan` +
`t_fanout_runtime`), `t_line_webhook.nim`/`t_line_runtime.nim` (US-005/006).
Os nomes reais foram mantidos onde o arquivo já existe; renomear só com ganho
claro, porque PRDs e revisões citam os nomes atuais.
