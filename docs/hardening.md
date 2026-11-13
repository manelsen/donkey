# Hardening P1 — stress, fault injection e recuperação

Este documento cobre a passada de endurecimento dos subsistemas entregues nos PRs #22–#28. O objetivo não é aumentar cobertura de produto, e sim provar comportamento sob concorrência, falha de I/O, rede instável e shutdown.

## Como rodar

```bash
# Suíte normal (stress é ignorado)
JOBS=6 bash scripts/run_tests.sh

# Suíte de stress (serial por padrão)
bash scripts/run_stress_tests.sh

# Soak por tempo (repete a suíte de stress)
SOAK_DURATION_SEC=600 bash scripts/run_soak.sh

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

## Browser hardening

O adapter de browser aplica a política em camadas:

- **Navegação:** só `http`/`https`, host público, todos os endereços DNS validados antes do `Page.navigate`.
- **Subrecurso e redirect:** `Fetch.requestPaused` valida cada hop; `Network.requestWillBeSent` revalida o destino de redirects como segunda camada.
- **Documento bloqueado:** navegação ou iframe para host privado aborta a sessão e fecha o browser.
- **WebSocket/WebTransport:** `Network.setBlockedURLs` bloqueia `ws://`, `wss://`, `ftp://`, `file://` e `filesystem://`; eventos `Network.webSocketCreated`/`webTransportCreated` são fail-closed.
- **Service worker:** `Network.setBypassServiceWorker`, script injetado que bloqueia registro/desregistra workers e eventos `ServiceWorker.*` que fecham a sessão.
- **Downloads:** `Browser.setDownloadBehavior`/`Page.setDownloadBehavior` com `deny`; se o build não expuser o método, fica um warning explícito.
- **Recursos:** `max_chars` é truncado dentro da página antes da serialização; screenshots acima de 8 MiB são recusados; `waitUntil` é validado.
- **Processo:** o browser recebe um env sanitizado (sem chaves de provider), perfil `0700`, portas CDP por usuário e flags que reduzem egress de background.

Variáveis:

| Variável | Default | Efeito |
|---|---:|---|
| `DONKEY_BROWSER_TIMEOUT_MS` | `30000` | timeout por comando CDP e por navegação; clamp `1000..120000` |
| `DONKEY_BROWSER_PROXY` | vazio | proxy filtrante para Edge/Chromium (Lightpanda é recusado) |
| `DONKEY_BROWSER_PROFILE_DIR` | vazio | diretório base de perfis persistentes; cada usuário recebe um subdiretório `0700` |

Em Chromium/Edge, falha ao instalar o script de política, ao bloquear URLs ou ao bypassar service worker aborta a navegação. Em Lightpanda, métodos CDP opcionais não suportados viram warning e a proteção remanescente é o `Fetch` + eventos + proxy/firewall.

## `execute_code`

`execute_code` só existe com sandbox declarado. Em `[sandbox] mode = "oci"` ele roda Python/JavaScript/shell em um container efêmero:

- `--network=none` sempre (não há opção de rede);
- rootfs read-only, `/tmp` tmpfs `noexec,nosuid` de 64 MiB;
- `--cap-drop=ALL`, `no-new-privileges`, `--pids-limit=128`, `--memory=512m`, `--cpus=1`, `--ulimit nofile=256:256`;
- bind mount apenas do paddock em `/workspace`, com o UID/GID do daemon;
- código passado como argv separado, sem shell do host;
- timeout externo com `timeout --kill-after`, cap de saída e `docker kill` de segurança;
- nenhum fallback para execução no host.

Em `[sandbox] mode = "wasm"`, `execute_code` aceita apenas `language = "wasm"` e um `wasm_path` dentro do paddock. O wasmtime recebe somente o workspace e um scratch isolado; nenhuma flag de socket/listener é adicionada. Quando `prlimit` está disponível, o endereço virtual do processo é limitado a 512 MiB; o timeout externo limita o tempo de CPU.

Variáveis:

| Variável | Default | Efeito |
|---|---:|---|
| `DONKEY_CODE_RUNTIME` | `sandbox.runtime` ou `docker` | runtime OCI usado por `execute_code` |
| `DONKEY_CODE_IMAGE` | `python:3.12-alpine` / `node:22-alpine` | imagem do container; deve conter o interpretador da linguagem |
| `DONKEY_CODE_TIMEOUT_SEC` | `10` | timeout de parede; clamp `1..60` |
| `DONKEY_CODE_MAX_OUTPUT_BYTES` | `65536` | cap de stdout+stderr; clamp `1024..1048576` |
| `DONKEY_CODE_MAX_SOURCE_BYTES` | `131072` | cap do código; clamp `1024..1048576` |

O tool é approval-gated por default (`DONKEY_APPROVAL_TOOLS` inclui `execute_code`) e a auditoria vai para o log do daemon com user, canal, linguagem, SHA-256 do código, duração, exit code, timeout/truncamento e imagem — nunca o código em si. Falha ao criar/consultar aprovação nega a execução.

## Threading e `gcsafe`

`gcsafe` é uma promessa estática do Nim, não um lock e não uma prova de thread-safety. `{.cast(gcsafe).}` desliga a checagem do compilador; usá-lo sem uma invariante real é “fazer de conta”.

O Donkey segue três regras:

- **Isolamento por thread:** os callbacks de `ToolRuntimePort` são declarados `gcsafe` por contrato. O `BrowserToolRuntime` guarda a thread dona e recusa `invoke`/`listTools` fora dela; `close`/`closeUser` retornam erro em vez de corridar. O callback `ToolRuntimePort.close` é `void` e descarta esse Result na fronteira, sem lançar exceção. A premissa é o event loop cooperativo do Chronos, não um lock.
- **Atomicidade real:** contadores globais de execução usam `Atomic[int]`; não há incremento “gcsafe” de `int` global.
- **Cast justificado:** quando um `{.cast(gcsafe).}` aparece, o escopo toca apenas estado local/thread-local ou está sob lock; o comentário no código diz qual é a invariante.

Se ferramentas passarem a rodar em múltiplas threads OS, o browser e o estado de sessão precisam de serialização explícita (lock/fila) ou de uma instância por thread. A anotação sozinha não cobre isso.

## Limites conhecidos (não resolvidos aqui)

- **Pinning de conexão do web fetch:** a resolução DNS é validada, mas o `std/httpclient` resolve novamente ao conectar. Em deployment exposto, use `DONKEY_WEB_PROXY` ou firewall de egress.
- **Pinning de conexão do browser:** o `Fetch` valida a URL, mas o browser resolve o host novamente ao conectar. Use `DONKEY_BROWSER_PROXY` ou firewall para pinar o IP validado; DNS rebinding não é eliminado localmente.
- **Browser:** WebSocket/service worker dependem do CDP do backend. O script injetado cobre páginas, não código já em execução antes da injeção; por isso o proxy/firewall continua sendo a garantia forte. Em Chromium a extração de conteúdo roda em isolated world; em Lightpanda o cap local + limite de frame CDP de 16 MiB limitam a saída, mas uma página hostil ainda pode forçar um frame grande até esse limite — prefira Chromium para conteúdo não confiável.
- **`execute_code`:** o isolamento é o do runtime OCI/WASI, não uma prova contra escape de kernel/container. A imagem é responsabilidade do operador; uma imagem sem o interpretador escolhido falha fechado. A execução é síncrona no actor de tools (como `bash`), então o timeout também limita o bloqueio do turno. O runner exige o comando GNU `timeout`; em macOS instale `coreutils` e garanta `timeout` no `PATH`.
- **Aprovação de código:** o resumo de aprovação mostra o código completo até 1500 caracteres; fontes maiores são recusadas para não aprovar uma ação truncada. Divida o programa ou aumente a revisão operacional antes de relaxar esse limite.
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
2. O browser usa `DONKEY_BROWSER_PROXY`; sem proxy, mantenha `DONKEY_BROWSER_BACKEND` em `chromium`/`edge` com o hardening CDP ativo.
3. Service workers/WebSocket do browser são bloqueados por CDP quando o backend suporta; DNS rebinding e pinning de conexão continuam dependendo do proxy/firewall.

## Drill operacional

O drill executado em 13/11/2026 está em `docs/ops-drill.md`: soak de 600s (24 execuções, 0 falhas), backup/restore do vault, corrupção/lost key, kill -9 no ledger e TLS. Ele também revelou e corrigiu permissões de `state/` (`0700`) e dos arquivos (`0600`).

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
