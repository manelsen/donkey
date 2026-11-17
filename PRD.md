[PRD]
# PRD: Mineração da experiência do hermes-agent — piloto Telegram

> **Executor:** agente autônomo. Leia este documento inteiro antes de começar. Execute as histórias **na ordem**. Cada história termina com os quality gates verdes e um commit próprio.

## 1. Contexto

O `hermes-agent` (NousResearch, licença MIT) é um agente em produção com cerca de 65 mil commits. O histórico dele concentra milhares de correções que revelam comportamentos reais das APIs externas. O Telegram é o canal principal do Donkey e é também o componente com mais correções no hermes: **718 commits de correção**, somando os que citam `telegram` no assunto e os que tocam `plugins/platforms/telegram`.

O Donkey tem arquitetura hexagonal com núcleo puro (`domain/`, `core/`), o que deixa barato absorver esse conhecimento como **funções puras com teste direto**. O objetivo é transferir o **diagnóstico** (o que a API faz), não a **solução** do hermes (como ele contornou).

Repositório de origem (**somente leitura**):

- Caminho: `$HERMES_DIR`, com default `/home/micelio/git/hermes-agent`.
- Commit de referência: `b3746e35dd`. Toda a mineração usa `git log b3746e35dd`, nunca `HEAD`, para ser reproduzível.

## 2. Objetivos

1. Gerar um inventário reproduzível das correções do hermes relacionadas ao Telegram.
2. Classificar cada correção como **conhecimento transferível** (comportamento da Bot API ou do Telegram) ou **interno do hermes** (descartado).
3. Consolidar as correções transferíveis em **casos** deduplicados, cada um com a lacuna no Donkey e uma prioridade.
4. Portar para o Donkey, com TDD, os casos P0 (no máximo 10 nesta rodada).
5. Deixar atribuição MIT, rastreabilidade (commit do hermes → teste do Donkey) e um processo incremental para as próximas rodadas.

## 3. Fora de escopo

- Outros canais e providers. O processo deve ser genérico, mas só o Telegram é executado agora.
- Recursos internos do hermes: perfis, `/handoff`, `/resume`, `/branch`, `/topic`, hosted rooms, kanban, adaptadores substitutos, leases, dashboard, desktop.
- Copiar código Python do hermes literalmente.
- Qualquer alteração no repositório do hermes.
- Rede, Telegram real, VPS, Docker real.

## 4. Quality gates

Obrigatórios ao fim de **toda** história:

```bash
bash scripts/check_boundaries.sh
nimble build -y
JOBS=6 bash scripts/run_tests.sh
git diff --check
```

Também obrigatório nas histórias que alteram o runtime do Telegram (`src/donkey/adapters/channel/telegram*.nim`):

```bash
bash scripts/run_stress_tests.sh
```

Regras adicionais:

- Nenhum teste novo usa rede, Telegram real ou Docker.
- `.gitignore` ignora `tests/**`, exceto `*.nim` e `tests/fixtures/**`. Fixtures JSON vão em `tests/fixtures/telegram/hermes/`.
- Lógica nova vai em `domain/` ou `core/` como `func` pura. O adapter só faz a ligação. Proibido `raise` fora de adapters; I/O falível retorna `Result[T, string]` (veja `CLAUDE.md`).
- TDD: escreva o teste, confirme que **falha**, implemente e confirme que **passa**.

## 5. Preparação (antes da US-001)

1. `cd ~/git/donkey && git status --short`. Se houver qualquer alteração, **pare** e registre no relatório final. Não use stash, reset ou checkout sobre trabalho alheio.
2. `git fetch origin && git switch master && git pull --ff-only`
3. `git switch -c feat/hermes-mining-telegram`
4. `git -C "$HERMES_DIR" cat-file -e b3746e35dd` precisa ter sucesso. Se falhar, pare e registre.

## 6. Histórias de usuário

### US-001: Proteger a pureza do `domain/` no check de fronteiras

**Por quê:** os casos portados vão para `domain/`, que hoje está limpo mas não é verificado pelo CI.

**Critérios de aceite:**
- [ ] `scripts/check_boundaries.sh` ganha um `check_absent` com a descrição `"domain must stay pure"` e o padrão `'^\s*(import|from)\s+.*(chronos|asyncsync|asyncdispatch|osproc|httpclient|parsetoml|adapters/|app/)'` sobre `src/donkey/domain`.
- [ ] O script passa no estado atual. Se falhar, **não** altere o código do domínio: registre os imports encontrados no relatório e ajuste o padrão apenas se o import for comprovadamente puro.
- [ ] Teste manual: adicionar temporariamente `import chronos` em um arquivo de `domain/` faz o script falhar. Reverta e cite o teste no commit.
- [ ] `tests/architecture/t_boundaries.nim` já executa o script; não o duplique. Ele passa a cobrir `domain/` automaticamente.
- [ ] Commit: `ci: enforce domain purity in boundary checks`.

### US-002: Script de extração reproduzível

**Critérios de aceite:**
- [ ] Criar `scripts/hermes_mine.sh` (bash, `set -euo pipefail`, sem Python) com a interface:
  `bash scripts/hermes_mine.sh <componente> [--since <hash>]`, onde `<componente>` = `telegram` nesta rodada.
- [ ] Variáveis: `HERMES_DIR` (default `/home/micelio/git/hermes-agent`) e `HERMES_REF` (default `b3746e35dd`).
- [ ] Para `telegram`, une e deduplica por hash:
  - `git -C "$HERMES_DIR" log "$HERMES_REF" --no-merges -i -E --grep='^fix.*telegram' --format='%H'`
  - `git -C "$HERMES_DIR" log "$HERMES_REF" --no-merges -i -E --grep='^fix' --format='%H' -- plugins/platforms/telegram`
- [ ] Com `--since <hash>`, usa o intervalo `<hash>..$HERMES_REF`.
- [ ] Grava `docs/hermes-mining/telegram/commits.tsv` com o cabeçalho
  `hash\tdate\tsubject\tfiles_changed\ttest_files` e uma linha por commit, ordenada por data crescente:
  - `hash`: 10 caracteres;
  - `date`: `%cs`;
  - `subject`: com tabs substituídos por espaço;
  - `files_changed`: quantidade de arquivos alterados;
  - `test_files`: caminhos de `tests/**/test_*.py` alterados, separados por `;`, ou `-`.
- [ ] Grava `docs/hermes-mining/telegram/LAST_SYNC` contendo o `HERMES_REF` usado.
- [ ] Rodar o script e commitar a saída. **Esperado: cerca de 718 linhas** (aceite de 700 a 730; fora disso, investigue e explique no commit).
- [ ] Rodar duas vezes produz arquivos idênticos (`diff` vazio).
- [ ] Commit: `feat(mining): reproducible hermes fix extraction for telegram`.

### US-003: Classificação das correções

**Critérios de aceite:**
- [ ] Criar `docs/hermes-mining/telegram/classification.tsv` com o cabeçalho
  `hash\tcategory\ttransfer\treason`, com **exatamente uma linha por commit** de `commits.tsv`.
- [ ] `category` precisa ser uma destas:

| category | significado | transfer |
|---|---|---|
| `RATE` | flood control, 429, `retry_after`, janelas de envio | yes |
| `FORMAT` | HTML/MarkdownV2, entidades, escape, limite de 4096, divisão de mensagem, código | yes |
| `MEDIA` | fotos, documentos, álbuns, voz, legendas, limites de tamanho, `file_id` | yes |
| `EDIT` | edição e exclusão de mensagem, streaming por edição, "message is not modified" | yes |
| `INBOUND` | parsing de updates, `callback_query`, ordem de chegada, duplicados, grupos e menções | yes |
| `NET` | polling, webhook, timeouts, nova tentativa em falha transitória, DNS/IP | yes |
| `TOPIC_API` | comportamento de **API** de forum topics e `message_thread_id` | yes |
| `INTERNAL` | recursos do hermes (lista da seção 3), refatoração, logs, nomes, testes do próprio hermes | no |
| `UNCLEAR` | não dá para decidir nem lendo o diff | no |

- [ ] Processo: classifique pelo `subject` primeiro. Rode `git -C "$HERMES_DIR" show --stat <hash>` e, se preciso, `git show <hash> -- '*.py'` **somente** quando o assunto for ambíguo.
- [ ] Ponto de partida para `INTERNAL`: o assunto contém `profile`, `handoff`, `/resume`, `/branch`, `/topic`, `hosted`, `room`, `kanban`, `replacement adapter`, `lease`, `dashboard`, `desktop`, `achievement`, `rename` (de sessão) ou `hermes send`.
- [ ] `reason`: no máximo 120 caracteres, em português, descrevendo o **comportamento da API** quando `transfer=yes`.
- [ ] Trabalhe em lotes de 50 commits, com um commit git por lote. Assim a tarefa pode ser retomada se for interrompida.
- [ ] Validação: `awk -F'\t' 'NR>1' classification.tsv | wc -l` igual a `awk -F'\t' 'NR>1' commits.tsv | wc -l`, e nenhuma categoria fora da tabela.
- [ ] `UNCLEAR` em no máximo 5% das linhas.
- [ ] Commits: `docs(mining): classify telegram fixes (batch N/M)`.

### US-004: Consolidação em casos e análise de lacunas

**Critérios de aceite:**
- [ ] Criar `docs/hermes-mining/telegram/CASES.md` agrupando as linhas `transfer=yes` em **casos deduplicados**. Vários commits sobre o mesmo comportamento formam um único caso.
- [ ] Cada caso segue exatamente este formato:

```markdown
### TG-001: <título curto do comportamento>
- **Categoria:** RATE
- **Comportamento da API:** <o que o Telegram faz, em 1–3 frases, sem citar código do hermes>
- **Gatilho / entrada:** <update, resposta ou erro que dispara o caso>
- **Comportamento esperado do cliente:** <o que um cliente correto deve fazer>
- **Fontes no hermes:** `abc1234567`, `def7654321`
- **Testes no hermes:** `tests/plugins/test_telegram_x.py::test_y` ou `-`
- **Situação no Donkey:** COBERTO | PARCIAL | AUSENTE
- **Evidência no Donkey:** `src/donkey/...:linha` e/ou `tests/...:linha` (obrigatório para COBERTO e PARCIAL; para AUSENTE, o comando `rg` usado na busca)
- **Prioridade:** P0 | P1 | P2
```

- [ ] Arquivos do Donkey a inspecionar para a situação:
  - `src/donkey/adapters/channel/telegram.nim`
  - `src/donkey/adapters/channel/telegram_runtime.nim`
  - `src/donkey/domain/channels/telegram_pure.nim`
  - `src/donkey/core/telegram_format.nim`
  - `src/donkey/core/outbound/`
  - `tests/channel/t_telegram.nim`
  - `tests/domain/channels/t_telegram_pure.nim`
- [ ] Prioridade:
  - **P0:** AUSENTE ou PARCIAL e (perde ou corrompe mensagem do usuário, trava o envio, ou leva o bot a ser limitado ou bloqueado pelo Telegram).
  - **P1:** AUSENTE ou PARCIAL e degrada a experiência (formatação errada, demora, duplicata visível).
  - **P2:** o resto, ou COBERTO.
- [ ] Ao final do arquivo, uma tabela-resumo com a contagem de casos por categoria × situação × prioridade.
- [ ] Commit: `docs(mining): consolidate telegram cases and donkey gap analysis`.

### US-005: Atribuição e rastreabilidade

**Critérios de aceite:**
- [ ] Criar `THIRD_PARTY_NOTICES.md` na raiz com uma seção `hermes-agent`: URL `https://github.com/nousresearch/hermes-agent`, o texto **completo** da licença MIT copiado de `$HERMES_DIR/LICENSE` e uma frase explicando que casos de teste e comportamentos foram derivados do histórico do projeto.
- [ ] Criar `docs/hermes-mining/TRACEABILITY.md` com a tabela
  `| Caso | Commits hermes | Teste Donkey | Implementação Donkey | Status |`
  com uma linha por caso P0 (status inicial `pendente`).
- [ ] Commit: `docs: add third-party notices and mining traceability`.

### US-006 … US-015: Portar os casos P0 (um caso por história)

Selecione os P0 de `CASES.md` em ordem de ID, **no máximo 10**. Se houver menos de 10 P0, complete com P1 até 10, ou pare se não houver P1. Para **cada** caso:

**Critérios de aceite:**
- [ ] **Red:** escreva os testes primeiro, em `tests/domain/channels/t_telegram_pure.nim` (lógica pura) ou num novo `tests/domain/channels/t_telegram_<tema>.nim`. O nome do teste começa com o ID: `test "TG-007: ..."`. Rode o teste e confirme que **falha**, registrando a falha na mensagem de commit.
- [ ] Se o caso envolver payload do Telegram, crie a fixture em `tests/fixtures/telegram/hermes/<TG-ID>_<descricao>.json`. Ela precisa ser um JSON **mínimo e anonimizado** (IDs fictícios, sem nomes reais), escrito à mão a partir do comportamento descrito, e não copiado das fixtures do hermes.
- [ ] **Green:** implemente como `func` pura em `src/donkey/domain/channels/` ou `src/donkey/core/`. Só então ligue no adapter (`telegram.nim` ou `telegram_runtime.nim`) com o mínimo de código.
- [ ] Primeira linha do bloco de documentação da função nova:
  `## Behavior derived from hermes-agent (MIT) fix <hash>; see docs/hermes-mining/telegram/CASES.md#tg-NNN`
- [ ] Não traduza código Python linha a linha; reimplemente a partir do comportamento descrito em `CASES.md`, no estilo do Donkey (`Result`, pipeops, `func`).
- [ ] Se tocar no runtime do Telegram, rode também o stress.
- [ ] Atualize a linha do caso em `TRACEABILITY.md` (teste, implementação, status `portado`) e marque o caso em `CASES.md` como `COBERTO`, com a nova evidência.
- [ ] Commit: `fix(telegram): TG-NNN <comportamento>`.

Se um caso se mostrar inviável sem rede ou Docker, ou exigir mudança de porta (`ports/`), **não** implemente: marque `adiado` em `TRACEABILITY.md` com o motivo e siga para o próximo.

### US-016: Processo incremental documentado

**Critérios de aceite:**
- [ ] Criar `docs/hermes-mining/README.md` com:
  - o objetivo e a regra "transferir diagnóstico, não solução";
  - como rodar `scripts/hermes_mine.sh telegram --since $(cat docs/hermes-mining/telegram/LAST_SYNC)` para uma rodada incremental, atualizando `HERMES_REF` para o novo `HEAD` do hermes;
  - como adaptar o script a outro componente: um bloco `case` por componente em `hermes_mine.sh`, com padrões de grep e caminhos;
  - as tabelas de categorias e de prioridades (as mesmas desta PRD);
  - as regras de atribuição.
- [ ] `hermes_mine.sh` com componente desconhecido sai com código 2 e mensagem listando os componentes suportados.
- [ ] Commit: `docs(mining): document incremental mining process`.

## 7. Regras de autonomia

- Não peça aprovação humana: a execução foi pré-aprovada.
- **Nunca** escreva em `$HERMES_DIR`: sem checkout, sem fetch, sem arquivos novos. Use apenas `git log`, `git show` e leitura de arquivos.
- Não acesse rede, exceto `git fetch`/`pull`/`push` do próprio Donkey.
- Não altere comportamento existente do Donkey fora do caso em execução. Se um teste existente quebrar, o problema está na sua mudança: corrija a mudança, não o teste.
- Se uma decisão não estiver especificada, escolha a opção mais conservadora e registre-a no relatório.
- Commits pequenos e claros, em inglês, sem `Co-Authored-By` nem crédito de IA.
- Ao terminar: `git push -u origin feat/hermes-mining-telegram` e abra um PR para `master` com `gh pr create`. No corpo, inclua o resumo do relatório final.

## 8. Relatório final

Crie `docs/hermes-mining/telegram/REPORT.md` contendo:

- o `HERMES_REF` usado e o total de commits extraídos;
- a contagem por categoria e por `transfer`;
- o número de casos por situação e prioridade;
- os casos portados, adiados (com motivo) e pendentes;
- a saída resumida de cada quality gate final (contagem de testes que passaram e falharam);
- as decisões tomadas sem especificação explícita;
- a branch, a lista de commits e o link do PR.

## 9. Métricas de sucesso

- `commits.tsv` reproduzível (duas execuções idênticas), com cerca de 718 linhas.
- `classification.tsv` cobre 100% dos commits, com no máximo 5% de `UNCLEAR`.
- `CASES.md` tem evidência verificável (`arquivo:linha` ou comando `rg`) em todos os casos.
- Até 10 casos portados, cada um com teste que falhava antes e passa depois.
- `check_boundaries.sh` cobre `domain/`; suíte normal e stress verdes; CI verde no PR.
- `THIRD_PARTY_NOTICES.md` presente, e todas as funções derivadas apontam para o caso de origem.
[/PRD]
