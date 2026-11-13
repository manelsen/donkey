# Hardening P1 — stress, fault injection e recuperação

Este documento cobre a passada de endurecimento dos subsistemas entregues nos PRs #22–#28. O objetivo não é aumentar cobertura de produto, e sim provar comportamento sob concorrência, falha de I/O, rede instável e shutdown.

## Como rodar

```bash
# Suíte normal (stress é ignorado)
JOBS=6 bash scripts/run_tests.sh

# Suíte de stress (serial por padrão)
bash scripts/run_stress_tests.sh

# Stress paralelo (use com cautela: testes compartilham /tmp)
JOBS=4 bash scripts/run_stress_tests.sh
```

O CI roda a suíte normal e, em seguida, a suíte de stress. Os testes de stress vivem em `tests/stress/` e só são compilados quando `DONKEY_STRESS=1` ou quando o alvo é `tests/stress`.

## Matriz de stress

| Arquivo | Cobre | Tempo esperado |
|---|---|---|
| `t_approval_store_stress.nim` | criações concorrentes, cap por usuário, decisão dupla | < 5s |
| `t_secret_vault_stress.nim` | `set`/`remove` concorrentes, leitores, lote grande, valor 32 KiB | < 5s |
| `t_ledger_worker_stress.nim` | appends concorrentes + compactação, stop idempotente | < 10s |
| `t_ssrf_corpus.nim` | userinfo, `@`, IPv6, IPv4 mapeado, redirects, DNS, `getNoRedirect` | < 5s |
| `t_webhook_tls_stress.nim` | 20 handshakes, 5 restarts, cliente TLS lento | < 15s |
| `t_slack_socket_stress.nim` | envelopes malformados, frame WebSocket, frame truncado | < 5s |

Tempo total esperado: **≤ 60s** de execução em runner Linux típico; o wrapper aplica `timeout` de 300s (configurável em `STRESS_TIMEOUT_SEC`) para cobrir compilação.

## O que foi provado

- O approval store serializa criações/decisões via `flock`; IDs são únicos e o cap de 8 pendentes por usuário é respeitado.
- O vault mantém JSON válido com escritores e leitores concorrentes; valores nunca aparecem em plaintext; 32 KiB roundtrip.
- O worker do ledger compacta enquanto 4 threads registram 400 entregas; nenhum registro é perdido e o stop retorna em < 2s.
- O SSRF bloqueia um corpus de autoridades privadas, inclusive `localhost.` (corrigido nesta passada) e `@` em path/query; redirects são revalidados por hop.
- O receiver TLS suporta 20 handshakes e 5 ciclos start/stop; um cliente TLS lento não impede o shutdown de terminar em < 10s.
- Envelopes Slack inválidos não lançam; frames WebSocket truncados geram erro de protocolo/reconexão, não timeout de idle.

## Limites conhecidos (não resolvidos aqui)

- **Pinning de conexão do web fetch:** a resolução DNS é validada, mas o `std/httpclient` resolve novamente ao conectar. Em deployment exposto, use `DONKEY_WEB_PROXY` ou firewall de egress.
- **Vault:** um backup do home inteiro inclui `.secret_key` e `.secrets/`; trate o backup como secreto. O vault não protege contra outro processo do mesmo usuário Unix.
- **Socket Mode:** o ack ocorre depois do enfileiramento, mas antes da resposta do usuário; o modelo é at-most-once para o turno. O shutdown dá uma janela de 2s para publicar respostas.
- **Ledger:** a compactação de startup é síncrona; não há lease/WAL/resume transacional.
- **TLS:** a recarga de certificado é por worker e depende de mtime; rotação ACME automática não existe.

## Recuperação

### Vault corrompido ou chave perdida

1. Pare o daemon.
2. Restaure `{home}/.secret_key` e `{home}/.secrets/secrets.json` do backup **juntos**.
3. Se a chave foi perdida, os valores são irrecuperáveis: mova `secrets.json` para backup, remova-o e recrie os segredos com `donkey ctl secret set`.
4. Verifique `ls -ld {home}/.secrets` (0700) e `ls -l {home}/.secret_key` (0600).
5. Inicie com `donkey start` e confira `donkey ctl secret list`.

### Approval store travado ou corrompido

1. Pare o daemon.
2. Faça backup de `state/approvals.json`.
3. Se houver JSON inválido, remova/renomeie o arquivo; pedidos pendentes serão perdidos e precisarão ser refeitos.
4. Arquivos `.tmp.*` órfãos podem ser removidos com o daemon parado. O `.lock` é recriado.
5. Reinicie e valide com `donkey ctl approval list`.

### Ledger corrompido

1. Pare o daemon.
2. Copie `state/delivery_ledger.jsonl` para inspeção.
3. O replay ignora JSON inválido em qualquer posição, então o histórico carregado pode omitir registros. Inspecione a cópia antes de considerá-lo recuperado. O compaction só recusa eventos futuros reconhecíveis por schema, não linhas inválidas.
4. Restaure o backup ou remova o arquivo (perde o histórico de entregas; sessões em `sessions.json` não são afetadas).
5. Reinicie; a compactação de startup recria o estado.

### Receiver TLS inválido ou rotação

1. Valide o par localmente:
   ```bash
   openssl x509 -in cert.pem -noout -subject -dates
   openssl rsa -in key.pem -check
   ```
2. Teste o handshake:
   ```bash
   openssl s_client -connect 127.0.0.1:${DONKEY_WEBHOOK_PORT:-8080} -servername localhost
   ```
3. Se o receiver não sobe, o startup falha fechado; não há fallback silencioso para HTTP.
4. Para rotacionar, substitua cert/key atomicamente (`mv` no mesmo filesystem). O worker recarrega no próximo handshake após o mtime mudar; se o novo par for inválido, mantém o anterior.
5. Se preferir centralizar TLS, remova `DONKEY_WEBHOOK_TLS_*` e use o proxy reverso.

### Socket Mode não recebe eventos

1. Confirme `SLACK_BOT_TOKEN` e `SLACK_APP_TOKEN` definidos.
2. No app Slack, confirme **Socket Mode** habilitado e o app-level token com `connections:write`.
3. Verifique logs `slack socket: connected` e `slack socket: idle timeout; reconnecting`.
4. Se envelopes forem reentregues, o dedupe por `event_id` evita turnos duplicados.
5. Para voltar ao webhook, remova `SLACK_APP_TOKEN`, configure `SLACK_SIGNING_SECRET` e `DONKEY_WEBHOOK_PORT`.

### Egress/SSRF

1. Se o host não tem firewall bloqueando destinos privados, configure `DONKEY_WEB_PROXY` para um proxy filtrante.
2. O browser usa `DONKEY_BROWSER_PROXY`.
3. Service workers/WebSocket do browser e DNS rebinding continuam dependendo do proxy/firewall.

## Política de release

Rode `bash scripts/run_stress_tests.sh` antes de release e depois de qualquer mudança em:

- locks, escrita atômica ou flock;
- criptografia, chave ou permissões;
- TLS/handshake/threads;
- resolução DNS, redirects ou proxy;
- shutdown, filas ou workers.

Falha de stress bloqueia release. Testes que viram flaky devem ser corrigidos, não ignorados.

## Instrumentação de teste

Os testes de contenção usam hooks opcionais, `nil` em produção:

- `ApprovalStore.onAfterTempWrite` / `SecretVault.onAfterTempWrite`: chamados sob o lock após gravar o temporário e antes do rename atômico;
- `RuntimeStateStore.onCompactStart`: chamado sob o lock no início de uma compactação real;
- `RuntimeStateStore.onAppendStart`: chamado antes de `recordPending` adquirir o lock.

Eles permitem provar contenção sem depender de sleeps ou ordem de scheduling; nenhum caminho de produção os define.
