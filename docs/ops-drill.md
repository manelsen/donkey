# Operational drill — 2026-11-13

Execução do drill operacional sobre o master `a64c0a5` (após PRs #29/#30). Objetivo: validar backup/restore, corrupção, kill -9, TLS e soak sem alterar dados reais.

## Ambiente

- Linux, Nim 2.2.8, build `nimble build -y`.
- Diretórios isolados em `/tmp/opencode/donkey-drill-*`.
- Nenhum token/provider real configurado.

## Resultados

### Soak

`SOAK_DURATION_SEC=600 bash scripts/run_soak.sh` repetiu a suíte de stress por ~10 minutos.

- Execuções: **24**
- Falhas: **0**
- Resultado: **600s contínuos, 6/6 testes de stress em todas as iterações**

### Vault — backup, restore, chave perdida e corrupção

1. Dois segredos gravados via `ctl secret set`; permissões observadas: `.secrets` 0700, `secrets.json`/`.secret_key` 0600.
2. Backup de `.secret_key` + `.secrets/` e restauração em um home limpo: `applyToEnv` retornou `applied=2`, `DRILL_TOKEN=drill-secret`.
3. Sem `.secret_key`, `ctl secret set` falhou com “key is missing” e `applyToEnv` falhou fechado.
4. JSON do vault corrompido: `ctl secret list` falhou com erro de parse; após restaurar o backup, voltou a listar os dois nomes.

### Ledger — kill -9 durante appends + compactação

Três execuções de `drill_ledger_writer` (appends contínuos + worker de compactação a cada 1s), kill -9 após 4s, seguidas de `drill_ledger_recover`:

| Run | Registros recuperados | `compact_error` | Modo do ledger |
|---|---:|---|---|
| 1 | 1928 | vazio | 600 |
| 2 | 2098 | vazio | 600 |
| 3 | 2113 | vazio | 600 |

O diretório de estado ficou `0700`. Nenhum replay falhou; linhas truncadas/compactação interrompida não corromperam o arquivo.

### TLS

`DONKEY_STRESS=1 bash scripts/run_tests.sh tests/stress/t_webhook_tls_stress.nim` passou:

- 20 handshakes TLS sequenciais;
- 5 ciclos start/stop;
- cliente lento não bloqueia shutdown;
- rotação inválida mantém o contexto anterior e registra a falha de recarga;
- startup com par inválido falha fechado.

## Achados e correções

1. **Permissões do estado:** `state/` e `delivery_ledger.jsonl` eram criados com `0775/0664` sob umask 002. O adapter `runtime_store` agora aplica `0700` no diretório e `0600` em `sessions.json` e no ledger; teste de permissões adicionado em `tests/app/t_durability.nim`.
2. **Chave ausente:** o vault falha fechado tanto na escrita quanto na leitura; restore da chave recupera os valores.
3. **Corrupção do vault:** erro explícito de parse; o operador deve restaurar o backup.
4. **Kill -9:** o framing por linha + rename atômico permitiram replay sem corrupção nos três cenários.
5. **TLS:** falha de rotação é fail-safe (contexto antigo continua) e startup inválido não abre o receiver.

## Limitações do drill

- Soak de ~10 minutos em um host; não substitui 24h de carga real.
- Sem injeção de disco cheio, rede lenta ou DNS rebinding real.
- O ledger de drill é sintético; não mede throughput de canais.
- A correção de permissões passa a valer na próxima escrita/compactação de instalações existentes; para migração imediata, `chmod 700 <home>/state` e `chmod 600 <home>/state/*.json*`.

## Reprodução

```bash
# soak
SOAK_DURATION_SEC=600 bash scripts/run_soak.sh

# helpers
nim c --hints:off -o:/tmp/drill_vault_apply scripts/drill/vault_apply.nim
nim c --hints:off -o:/tmp/drill_ledger_writer scripts/drill/ledger_writer.nim
nim c --hints:off -o:/tmp/drill_ledger_recover scripts/drill/ledger_recover.nim

# kill -9
/tmp/drill_ledger_writer /tmp/ledger-drill &
sleep 4; kill -9 $!
/tmp/drill_ledger_recover /tmp/ledger-drill

# TLS
DONKEY_STRESS=1 JOBS=1 bash scripts/run_tests.sh tests/stress/t_webhook_tls_stress.nim
```
