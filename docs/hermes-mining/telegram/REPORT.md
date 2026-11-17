# Relatório — mineração do hermes-agent para o Telegram

## Escopo

- `HERMES_REF`: `b3746e35dd`
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
| COBERTO | 19 |
| PARCIAL | 9 |
| AUSENTE | 9 |

| Prioridade | Casos |
|---|---|
| P0 | 6 |
| P1 | 15 |
| P2 | 16 |

## Casos portados nesta rodada

Dez casos, cada um com teste que falhava antes da implementação:

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

## Casos adiados

| Caso | Motivo |
|---|---|
| TG-021 | Evitar duplicata em timeout de envio exige distinguir POST idempotente no `HttpPort`, que é compartilhado por todos os canais. Fora do escopo desta rodada. |

## Casos pendentes

Os 26 casos restantes de `CASES.md` (P1/P2) ficam registrados com evidência e
prioridade para as próximas rodadas. Os P1 com maior impacto são TG-012
(janela de flood por chat), TG-013 (retomar da parte recusada), TG-015 (menções
em grupo), TG-020 (409 no polling), TG-025/TG-026 (forum topics), TG-027
(foto grande vira documento), TG-028 (álbuns) e TG-031 (finalização de
streaming).

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
- **TG-021 adiado** em vez de alterar a política de retry do `HttpPort`, que
  afetaria todos os canais.
- **Marcador de corte na legenda**: `clipCaption` acrescenta `…` para deixar
  visível que o texto foi cortado.
- **Fences exigem início de linha**: uma sequência de três crases no meio de
  uma linha é tratada como código inline, não como bloco.

## Branch, commits e PR

- Branch: `feat/hermes-mining-telegram`
- PR: preenchido em `docs/hermes-mining/telegram/REPORT.md` no corpo do PR.

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
