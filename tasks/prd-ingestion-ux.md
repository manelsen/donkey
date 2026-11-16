[PRD]
# PRD: Ingestão de anexos e memória — correção do incidente de 15/11/2026

> **Status:** implementado na branch `fix/ingestion-ux`. Este documento fica como especificação e checklist de verificação; os critérios de aceite foram cobertos pelos testes citados.

## 1. Visão geral

Em 15/11/2026, o envio de `Memory Export.md` pelo Telegram falhou em cadeia:

1. o arquivo foi salvo em `~/.local/bin/downloads/<uuid>/file_1.md`, fora do paddock;
2. o `file_id` do Telegram foi enviado ao provider como `imageUrl`, causando erro 400;
3. o `/doctor` testou o provider padrão, não o provider ativo do usuário;
4. o sandbox OCI falhou por falta do grupo `docker` no serviço systemd --user;
5. o gate de aprovação rejeitou o `fs_write` de 26 KB e o agente fatiou o arquivo em ~30 escritas;
6. o `MANEL_PROFILE.md` foi criado, mas o runtime de memória não lê arquivos arbitrários do paddock;
7. o perfil antigo (`Void`) continuou prevalecendo sobre o export novo (`Manel`).

Este PRD corrige o fluxo de ponta a ponta, com testes de regressão que não dependem de Docker, rede ou Telegram real. A execução é autônoma: nenhuma história exige aprovação humana e o agente deve tomar as decisões indicadas abaixo.

## 2. Objetivos

- Todo anexo recebido por um canal é salvo dentro do paddock do usuário e fica legível por `fs_read`/`text_read`/`inspect_image`.
- Nenhum `file_id` de canal é enviado como `imageUrl` ao provider.
- `/doctor` testa o provider/modelo ativo do usuário e reporta a falha real.
- O agente consegue ingerir um arquivo de texto na memória sem passar o conteúdo inteiro pelo LLM.
- Escritas grandes podem ser aprovadas em uma única ação, com opt-in explícito e resumo verificável.
- Paddocks e arquivos sensíveis nascem com permissões `0700`/`0600`.
- O erro de sandbox por permissão do Docker é explicado com o comando de correção.
- O incidente fica coberto por um teste de regressão fim a fim.

## 3. Quality Gates

Estes comandos devem passar para toda história:

- `bash scripts/check_boundaries.sh`
- `nimble build -y`
- `JOBS=6 bash scripts/run_tests.sh`
- `git diff --check`

Para histórias que tocam runtime assíncrono, concorrência, sandbox ou o fluxo de anexos, também:

- `bash scripts/run_stress_tests.sh`

Antes do commit final da última história:

- `JOBS=6 bash scripts/run_tests.sh`
- `bash scripts/run_stress_tests.sh`
- `nimble build -y`
- `git status --short` limpo após o commit

Critérios adicionais:

- Nenhum teste novo depende de rede, Docker real, Telegram real ou browser.
- Testes usam diretórios temporários e portas falsas.
- O código compila com e sem `-d:withSqlite`/`-d:withPostgres`; a lógica usa `MemoryRuntimePort`, não o adapter concreto.
- Mudanças de segurança preservam o default atual e introduzem opt-in explícito quando necessário.

## 4. Histórias de usuário

### US-001: Salvar anexos dentro do paddock

**Descrição:** Como usuário do Telegram, quero que um documento enviado seja salvo no meu paddock e fique acessível às ferramentas nativas, para que o agente consiga lê-lo sem adivinhar caminhos.

**Critérios de aceite:**
- [ ] Criar `src/donkey/app/inbound_media.nim` com `applyInboundAttachment(msg: var InboundMessage; download: FileDownload; paddockDir: string; preferredName = ""; preferredMime = ""): Result[InboundAttachment, string]`.
- [ ] `InboundAttachment` expõe `relPath`, `absPath`, `mimeType`, `size` e `isImage`.
- [ ] O arquivo é salvo em `{paddockDir}/attachments/`, com nome sanitizado (sem `/`, `\`, `..`, caracteres de controle; fallback `attachment`).
- [ ] Em POSIX, o diretório `attachments` fica `0700` e o arquivo `0600`.
- [ ] `msg.text` recebe um marcador legível: `[Anexo: attachments/<nome> (<mime>, <N> bytes). Use fs_read ou text_read para ler o conteúdo.]`.
- [ ] Para MIME `image/*`, o marcador orienta `inspect_image` com o caminho relativo.
- [ ] `msg.mediaUrl` é sempre esvaziado após o salvamento, para que nenhum `file_id` chegue ao provider.
- [ ] `processInboundMediaDownload` em `src/donkey.nim` passa a receber `msg: var InboundMessage` e `paddockDir: string`, e vira um wrapper fino de `applyInboundAttachment`.
- [ ] Os dois call sites passam `memory.paddockDir(msg.userId)`; o campo `runtime.downloadDir` e o default `getAppDir()/downloads` são removidos.
- [ ] Novo `tests/app/t_inbound_media.nim` prova: conteúdo salvo, caminho relativo correto, marcador presente, `mediaUrl == ""`, nome sanitizado e permissões POSIX.
- [ ] Teste com nome malicioso (`../../etc/passwd`) prova que o arquivo não escapa de `attachments/`.

### US-002: Preservar nome e MIME do documento do Telegram

**Descrição:** Como usuário, quero que o arquivo mantenha o nome original (`Memory Export.md`) em vez de virar `file_1.md`, para que o agente e eu reconheçamos o conteúdo.

**Critérios de aceite:**
- [ ] `TgParseResult` em `src/donkey/domain/channels/telegram_pure.nim` ganha `mediaFileName` e `mediaMimeType`.
- [ ] `parseUpdate` lê `document.file_name` e `document.mime_type`.
- [ ] Para `photo`, usa nome sintético `photo.jpg` e MIME `image/jpeg`; para `voice`, `voice.ogg` e `audio/ogg`.
- [ ] `InboundMessage` em `src/donkey/domain/message.nim` ganha `mediaFileName` e `mediaMimeType`, copiados em `toInbound`.
- [ ] `TelegramAdapter.receive` copia os campos para a mensagem inbound.
- [ ] `processInboundMediaDownload` passa os campos como `preferredName`/`preferredMime` para `applyInboundAttachment`.
- [ ] Teste em `tests/domain/channels/t_telegram_pure.nim` cobre documento com nome/MIME e foto.
- [ ] Teste em `tests/app/t_inbound_media.nim` prova que o nome preferido é usado e sanitizado.

### US-003: `/doctor` testa o provider ativo do usuário

**Descrição:** Como usuário, quero que o `/doctor` teste o mesmo provider/modelo que o chat usa, para não receber “Provider: OK” enquanto as mensagens falham.

**Critérios de aceite:**
- [ ] `buildDoctorReport` em `src/donkey/adapters/channel/common_runtime.nim` carrega `memory.loadContext(userId).preferencesMd` e chama `completeBuilder(prefs)`.
- [ ] O relatório mostra o provider/modelo ativo e, em caso de falha, o erro retornado (truncado em 300 chars).
- [ ] A lista de API keys do relatório inclui Groq, DeepSeek e OpenAI, sem imprimir valores.
- [ ] Teste em `tests/adapters/channel/` (ou `tests/app/`) usa um `completeBuilder` falso que captura o `preferencesMd` recebido; o teste prova que o valor é o do usuário, não `""`.
- [ ] O teste não faz chamada de rede: o builder falso retorna `ok`.
- [ ] O relatório continua funcionando quando `PREFERENCES.md` está vazio (usa o default).

### US-004: Diagnóstico e mensagem clara do sandbox Docker

**Descrição:** Como operador, quero que o Donkey detecte que o serviço não tem acesso ao socket do Docker e explique o grupo `docker`, em vez de repetir “permission denied” em cada tool.

**Critérios de aceite:**
- [ ] `sandboxAvailabilityResult` em `src/donkey/app/sandbox.nim`, para `smOci`, verifica o binário e o acesso ao socket (`docker info` com timeout curto ou teste de `fileExists` + permissão).
- [ ] Em falha de permissão, a mensagem inclui: `sudo usermod -aG docker $USER`, `systemctl --user restart donkey` e a alternativa de reboot/`user@<uid>.service`.
- [ ] `donkey doctor` (`src/donkey/app/doctor.nim`) inclui o check de socket quando `sandbox.mode = "oci"` e o marca como `dsErr`.
- [ ] `sandboxBash`/`executeOciPlan` mapeiam `permission denied ... docker.sock` para a mesma mensagem acionável.
- [ ] Teste em `tests/app/t_doctor.nim` (ou existente) usa um runtime falso que falha e prova que o detalhe contém o comando do grupo.
- [ ] Teste de `sandboxBash` com runtime falso prova que a mensagem final contém `docker` e `usermod`.
- [ ] Nenhum teste requer Docker real.

### US-005: Tool `memory_ingest`

**Descrição:** Como usuário, quero pedir “ingira este arquivo na memória” e ter o conteúdo realmente adicionado ao grafo/MEMORY, sem que o LLM precise copiar 26 KB no contexto.

**Critérios de aceite:**
- [ ] Adicionar `MemoryIngestToolName = "memory_ingest"`, descrição e schema em `src/donkey/domain/` (seguir o padrão de `builtin_tools.nim`/`more_tools.nim`).
- [ ] Schema aceita `path` (string, opcional) **ou** `text` (string, opcional), exatamente um; `chunk_chars` (default 2000, clamp 500..8000) e `max_chunks` (default 100, clamp 1..500).
- [ ] O handler resolve `path` com o mesmo `resolvedToolPath` de `fs_read` (restrito ao paddock), rejeita diretório, arquivo binário e arquivo > 2 MB.
- [ ] O conteúdo é dividido em chunks preservando UTF-8, preferindo quebras de linha/parágrafos; cada chunk chama `ctx.memory.appendMemory(ctx.uid, chunk)`.
- [ ] O resultado retorna `{"ok":true,"chunks":N,"bytes":M,"path":"..."}`; `text` é aceito sem path.
- [ ] A tool não passa pelo approval gate (é leitura + memória), mas conta no budget de tool calls.
- [ ] Adicionar a tool em `nativeSessionTools` (`session_bootstrap.nim`) e no dispatch/categoria correta em `native_tools.nim`/`native_tool_dispatch.nim`.
- [ ] Novo `tests/app/t_memory_ingest.nim` usa um `MemoryRuntimePort` falso que captura `appendMemory`; prova chunks > 1, conteúdo preservado, path fora do paddock rejeitado, binário rejeitado e entrada vazia rejeitada.
- [ ] Documentar a tool no `README.md`/`docs/` na história de docs.

### US-006: Aprovação de writes grandes com resumo (opt-in)

**Descrição:** Como usuário, quero aprovar uma escrita grande de uma vez, vendo caminho, tamanho, hash e prévia, em vez de aprovar 30 appends.

**Critérios de aceite:**
- [ ] Adicionar `DONKEY_APPROVAL_LARGE_WRITES` com valores `reject` (default) e `summary`.
- [ ] Em `summary`, `fs_write` e `text_replace` acima de 1500 chars geram um resumo estruturado: `path`, `mode`, `bytes`, `sha1` e prévia de até 800 chars; o resumo nunca é vazio.
- [ ] Em `reject`, o comportamento atual é preservado e o teste `oversized approval action is blocked instead of truncated` continua passando.
- [ ] `bash`, `execute_code` e `edit_file` continuam bloqueados acima do limite em ambos os modos.
- [ ] O resumo é escapado para Telegram (sem quebrar markdown) e não inclui o conteúdo inteiro.
- [ ] Teste em `tests/app/t_native_approval.nim`: modo `summary` cria aprovação para `fs_write` grande e o summary contém path/bytes/sha1; modo `reject` mantém `too large`.
- [ ] `deploy/donkey.env.example` e docs listam a variável com o default `reject`.

### US-007: Permissões 0700/0600 no paddock

**Descrição:** Como operador, quero que dados de memória e sessões não sejam legíveis por outros usuários do VPS (incluindo `boinc`).

**Critérios de aceite:**
- [ ] `MdFileAdapter.ensurePaddock` em `src/donkey/adapters/memory/md_file.nim` cria/chmoda o paddock, `sessions/` e `attachments/` como `0700` em POSIX.
- [ ] `saveUserMd`, `appendMemory`, `savePreferences`, `saveSession`, `saveIdentity` e writes de `HEARTBEAT.md` aplicam `0600` após escrever.
- [ ] `ensurePaddock` também corrige permissões de arquivos existentes conhecidos (`USER.md`, `MEMORY.md`, `PREFERENCES.md`, `HEARTBEAT.md`, `sessions/*`, `attachments/*`), sem apagar conteúdo.
- [ ] A correção é idempotente e não falha se o arquivo não existir.
- [ ] Teste em `tests/memory/t_md_permissions.nim` (ou existente) cria paddock com permissões frouxas, chama `loadContext`/`ensurePaddock` e verifica `0700`/`0600` em POSIX.
- [ ] Em plataformas não-POSIX, as chamadas são no-op e os testes são pulados.
- [ ] O README/documentação menciona que paddocks são privados por padrão.

### US-008: Mensagens de erro de provider mais úteis

**Descrição:** Como usuário, quero saber se o erro foi anexo inválido, autenticação, rate limit ou falha temporária, em vez de “ocorreu um erro”.

**Critérios de aceite:**
- [ ] `genericProviderErrorText` em `src/donkey/app/prompt_building.nim` reconhece `image_url`, `image`, `file_id`, `invalid content`, `unsupported` e retorna uma mensagem específica sobre anexo/modelo.
- [ ] O log do `tool_loop_runtime` registra o erro bruto do provider (truncado em 500 chars) em nível `warn` antes de enviar a mensagem genérica.
- [ ] Teste em `tests/app/t_prompt_building.nim` cobre: erro de imagem, 401, 429 e erro desconhecido.
- [ ] Nenhum segredo/token aparece na mensagem ou no log de teste.

### US-009: Documentação e exemplo de ambiente

**Descrição:** Como operador, quero que o comportamento novo esteja documentado para eu configurar o VPS sem redescobrir o incidente.

**Critérios de aceite:**
- [ ] `README.md` (ou `docs/topics/`) documenta: anexos em `attachments/`, uso de `fs_read`/`inspect_image`, `memory_ingest`, `DONKEY_APPROVAL_LARGE_WRITES`, permissões de paddock e o check de Docker do doctor.
- [ ] `deploy/donkey.env.example` inclui `DONKEY_APPROVAL_LARGE_WRITES=reject` e uma nota sobre `DONKEY_APPROVAL_TOOLS`.
- [ ] `docs/` menciona que `MANEL_PROFILE.md` não é ingerido automaticamente; usar `memory_ingest`.
- [ ] Nenhum exemplo contém token, chave ou dado pessoal real.

### US-010: Regressão fim a fim e fechamento

**Descrição:** Como mantenedor, quero um teste que reproduza o incidente sem Telegram/Docker e prove que o fluxo corrigido funciona.

**Critérios de aceite:**
- [ ] Teste `tests/app/t_ingestion_regression.nim` monta um update JSON de documento do Telegram, passa por `parseUpdate` → `toInbound` → `encodeSessionPayload` → `decodeUserPayload`.
- [ ] O teste salva o anexo em um paddock temporário via `applyInboundAttachment` e prova que: o arquivo existe em `attachments/`, o payload contém o caminho relativo, `mediaUrl` está vazio e o conteúdo pode ser lido por `fs_read`/`readFile`.
- [ ] O teste prova que o arquivo NÃO é gravado em `getAppDir()/downloads`.
- [ ] `JOBS=6 bash scripts/run_tests.sh` passa.
- [ ] `bash scripts/run_stress_tests.sh` passa.
- [ ] `nimble build -y` passa e o binário `donkey` é gerado.
- [ ] `git diff --check` passa; working tree limpo após o commit final.
- [ ] Abrir PR para `master` com resumo do incidente, mudanças e comandos de validação; se `gh` não estiver autenticado, deixar o branch pronto e registrar o comando de PR no relatório final.

## 5. Requisitos funcionais

- FR-1: Anexos inbound são persistidos em `{paddock}/attachments/` e referenciados por caminho relativo no turno do usuário.
- FR-2: Nenhum identificador de arquivo de canal (`file_id`, `mediaId`) é usado como URL de imagem no provider.
- FR-3: Imagens usam `inspect_image` com caminho local; documentos usam `fs_read`/`text_read`.
- FR-4: `/doctor` usa as preferências do usuário para testar o provider ativo.
- FR-5: `memory_ingest` lê um arquivo do paddock ou texto e chama `appendMemory` em chunks limitados.
- FR-6: Escritas grandes podem ser aprovadas com resumo (`path`, bytes, sha1, prévia) quando `DONKEY_APPROVAL_LARGE_WRITES=summary`.
- FR-7: Paddocks, sessões e anexos têm permissões privadas em POSIX.
- FR-8: Erros de anexo/provider são distinguíveis e acionáveis.
- FR-9: O comportamento é coberto por testes que não exigem serviços externos.

## 6. Não-objetivos

- Implementar upload de arquivos grandes (> 20 MB) ou streaming de anexos.
- Integrar o Telegram real nos testes.
- Resolver o conflito de identidade “Manel vs Void” automaticamente; o agente não deve sobrescrever `USER.md` sem instrução explícita.
- Implementar `ctl memory import` destrutivo ou migração automática do grafo.
- Mudar o default de segurança do approval gate; o modo `summary` é opt-in.
- Corrigir a fragmentação de mensagens longas do Telegram além do necessário para o fluxo de anexos.
- Alterar o VPS ou o serviço em produção; o trabalho é código + testes + docs.

## 7. Considerações técnicas

- `InboundMessage` e `TgParseResult` são tipos de domínio; mudanças devem ser aditivas para não quebrar adapters.
- `FileDownload` vive em `src/donkey/ports/channel.nim`; `saveFileToDisk` vive em `src/donkey/core/media_download.nim`.
- O app layer pode importar `domain`, `core` e `ports`; não importar `adapters` (respeitar `scripts/check_boundaries.sh`).
- `applyInboundAttachment` deve ser testável sem `DaemonRuntime`; a integração em `src/donkey.nim` fica fina.
- `resolvedToolPath` já implementa a restrição ao paddock; reutilizar em `memory_ingest`.
- O `MemoryRuntimePort` tem `appendMemory`; usar a porta, não `MagmaMemoryAdapter`, para compilar com e sem SQLite.
- `setFilePermissions` é POSIX; usar `when defined(posix)` e manter Windows compilando.
- O resumo de aprovação usa `checksums/sha1` (já é dependência) e deve escapar quebras de linha.
- A tool `memory_ingest` deve ter caps duros para evitar encher o grafo; `max_chunks` e `max bytes` são obrigatórios.
- O teste de regressão deve usar um `FileDownload` fake e um `OutboundChannelPort.downloadFile` fake; não chamar Telegram.

## 8. Sequência de entrega

1. US-001 — pipeline de anexos (base).
2. US-002 — nome/MIME do Telegram.
3. US-003 — doctor ativo.
4. US-004 — sandbox/Docker.
5. US-005 — memory_ingest.
6. US-006 — approval summary opt-in.
7. US-007 — permissões.
8. US-008 — erros de provider.
9. US-009 — docs.
10. US-010 — regressão e fechamento.

Cada história deve ser um commit independente. US-002 depende de US-001. US-005 pode ser feita depois de US-001. US-010 depende de todas.

## 9. Regras de autonomia

- Não pedir aprovação humana; o usuário pré-aprovou a execução.
- Não acessar o VPS, o Telegram real ou o serviço em produção.
- Não apagar dados de usuário; migrações de permissão são restritivas e idempotentes.
- Se houver conflito entre uma história e um teste de segurança existente, preservar o default seguro e implementar opt-in.
- Se uma decisão não estiver especificada, escolher a opção mais conservadora que ainda cumpra o objetivo.
- Commits pequenos, mensagens claras, sem `Co-Authored-By` ou crédito de IA.
- Ao final, registrar no relatório: comandos rodados, resultados, branch, commits e PR (se aberto).

## 10. Status de implementação

- US-001..US-010 implementadas na branch `fix/ingestion-ux`.
- `bash scripts/check_boundaries.sh`: passou.
- `nimble build -y`: passou.
- `JOBS=6 bash scripts/run_tests.sh`: 213 passaram, 0 falharam.
- `bash scripts/run_stress_tests.sh`: 6 passaram, 0 falharam.
- `git diff --check`: passou.

## 11. Métricas de sucesso

- Um arquivo `.md` enviado pelo Telegram é salvo em `{paddock}/attachments/` e o agente consegue lê-lo com `fs_read`.
- Nenhum teste de anexo envia `file_id` como `imageUrl`.
- `/doctor` falha quando o provider ativo falha e passa quando ele responde.
- `memory_ingest` adiciona o conteúdo ao `MemoryRuntimePort` em chunks, sem estourar o contexto.
- Um `fs_write` de 26 KB é aprovado uma vez no modo `summary`.
- `loadContext` deixa paddock/sessões/anexos com `0700`/`0600`.
- Suíte normal e stress verdes; CI verde.
[/PRD]
