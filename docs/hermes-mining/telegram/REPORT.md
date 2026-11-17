# Relatório — mineração do hermes-agent para o Telegram

## Escopo

- `HERMES_REF`: `b3746e35dd` (o `LAST_SYNC` grava o SHA completo resolvido)
- Commits extraídos: **718** (faixa esperada 700–730)
- Repositório de origem lido apenas com `git log`, `git show` e `git cat-file`.
- Nenhum teste novo usa rede, Telegram real ou Docker.

## Contagem por categoria

| Categoria | Commits | Transfer |
|---|---|---|
| INTERNAL | 167 | no |
| NET | 120 | yes |
| INBOUND | 118 | yes |
| FORMAT | 106 | yes |
| TOPIC_API | 87 | yes |
| MEDIA | 65 | yes |
| RATE | 29 | yes |
| EDIT | 26 | yes |
| UNCLEAR | 0 | no |
| **Total** | **718** | 551 yes / 167 no |

`UNCLEAR` ficou em 0% (limite de 5%). A classificação foi feita em lotes de 50
commits, com um commit por lote, e validada contra a ordem e o conjunto de
hashes de `commits.tsv`.

## Casos consolidados

37 casos em [`CASES.md`](CASES.md), agrupando os 551 commits transferíveis por
comportamento (não por commit).

| Situação | Casos |
|---|---|
| COBERTO | 36 |
| PARCIAL | 1 |
| AUSENTE | 0 |

| Prioridade | Casos |
|---|---|
| P0 | 6 |
| P1 | 15 |
| P2 | 16 |

## Casos portados nesta rodada

Vinte e sete casos, cada um com teste que falhava antes da implementação:

| Caso | Comportamento | Teste |
|---|---|---|
| TG-001 | limite de 4096 em unidades UTF-16 | `tests/domain/channels/t_telegram_split.nim` |
| TG-002 | "message is not modified" é sucesso | `tests/domain/channels/t_telegram_policy.nim` |
| TG-003 | updates de bots são ignorados | `tests/domain/channels/t_telegram_pure.nim` |
| TG-004 | update sem `from` não derruba o parsing | `tests/domain/channels/t_telegram_pure.nim` |
| TG-005 | âncora de resposta inexistente é descartada | `tests/domain/channels/t_telegram_policy.nim` |
| TG-006 | texto vazio não é enviado | `tests/domain/channels/t_telegram_policy.nim` |
| TG-007 | legenda limitada a 1024 caracteres | `tests/domain/channels/t_telegram_policy.nim` |
| TG-008 | edição acima de 4096 vira edição + cauda | `tests/domain/channels/t_telegram_policy.nim` |
| TG-009 | `callback_data` limitado a 64 bytes | `tests/domain/channels/t_telegram_policy.nim` |
| TG-033 | fences por tamanho da sequência e CRLF | `tests/core/t_telegram_format.nim` |
| TG-021 | envio não idempotente não é repetido | `tests/http/t_std_http.nim` |
| TG-022 | proxy, timeout e allowlist ligados no adapter | `tests/channel/t_telegram.nim` |
| TG-027 | foto recusada cai para documento | `tests/domain/channels/t_telegram_policy.nim` |
| TG-030 | upload de mídia com prazo próprio | `tests/channel/t_telegram.nim` |
| TG-035 | prévia de link desativada por padrão | `tests/domain/channels/t_telegram_policy.nim` |
| TG-036 | menu de comandos dentro dos limites da API | `tests/core/t_command_catalog.nim` |
| TG-012 | janela de flood por chat | `tests/core/t_flood_gate.nim` |
| TG-013 | resposta dividida retoma da parte recusada | `tests/core/t_flood_gate.nim` |
| TG-031 | edição final recusada entrega a resposta | `tests/app/t_outbound_runtime.nim` |
| TG-010 | ação de digitação re-armada durante o turno | `tests/app/t_orchestrator.nim` |
| TG-015 | gate de menção em grupos | `tests/domain/channels/t_telegram_policy.nim` |
| TG-020 | 409 do polling repetido com backoff | `tests/http/t_std_http.nim` |
| TG-025 | resposta dentro do forum topic | `tests/domain/channels/t_telegram_policy.nim` |
| TG-026 | thread apagado cai para o chat raiz | `tests/domain/channels/t_telegram_policy.nim` |
| TG-028 | álbum mantém todos os anexos que caem na mesma janela de debounce | `tests/app/t_orchestrator.nim` |
| TG-029 | voz e áudio nos métodos próprios | `tests/domain/channels/t_telegram_policy.nim` |
| TG-037 | escape de texto dinâmico em Markdown | `tests/core/t_telegram_format.nim` |

Nota sobre TG-028: a união dos anexos depende da janela de
`collectWithDebounce`. O teste cobre `mergeUserPayloads` e
`addUserTurnWithImages`; a chegada real dos updates e o coletor não são
exercitados por ele. Além disso, só o caminho OpenRouter serializa `imageUrl`
hoje (`openrouter.nim:74`); Anthropic e Gemini exigiriam baixar e codificar a
imagem, o que é uma mudança de provider fora dos casos de Telegram.

## Casos adiados

Nenhum.

## Casos pendentes

Dos 37 casos, 36 estão COBERTO. Resta **1 caso PARCIAL**: TG-016 (recorte de
allowlist por grupo), que pertence ao balde de diferenças de arquitetura e não
aos baldes 1 e 3.

## Quality gates finais

| Gate | Resultado |
|---|---|
| `bash scripts/check_boundaries.sh` | passou (inclui a nova regra de pureza de `domain/`) |
| `nimble build -y` | passou |
| `JOBS=6 bash scripts/run_tests.sh` | **224 arquivos de teste, 0 falhas** |
| `bash scripts/run_stress_tests.sh` | 6 testes, 0 falhas |
| `git diff --check` | limpo |

## Decisões tomadas sem especificação explícita

- **`docs/` no `.gitignore`**: o padrão antigo ignorava o diretório inteiro.
  Trocado por `docs/*` com exceção para `docs/hermes-mining/`, para versionar
  apenas a mineração sem abrir o resto da documentação.
- **Classificação assistida**: as regras de categorização foram aplicadas em
  seis lotes independentes e revisadas; nenhuma linha ficou `UNCLEAR`.
- **Casos por comportamento, não por commit**: 551 commits transferíveis
  viraram 37 casos. Commits do mesmo comportamento apontam para o mesmo caso.
- **TG-021 resolvido sem mudar a porta**: o retry passou a ser decidido por
  tipo de método no `StdHttpAdapter` (`retryNonIdempotent`), e só o adapter do
  Telegram o desliga; os demais canais mantêm o comportamento anterior.
- **Marcador de corte na legenda**: `clipCaption` acrescenta `…` para deixar
  visível que o texto foi cortado.
- **Fences exigem início de linha**: uma sequência de três crases no meio de
  uma linha é tratada como código inline, não como bloco.

## Branch, commits e PR

- Branch: `feat/hermes-mining-telegram`
- PR: https://github.com/manelsen/donkey/pull/48 (merge `f3556c6`)

Commits da rodada, em ordem:

```
ci: enforce domain purity in boundary checks
feat(mining): reproducible hermes fix extraction for telegram
docs(mining): classify telegram fixes (batch 1/15) … (batch 15/15)
docs(mining): consolidate telegram cases and donkey gap analysis
docs: add third-party notices and mining traceability
fix(telegram): TG-001 … TG-009, TG-033
docs(mining): document incremental mining process
```
