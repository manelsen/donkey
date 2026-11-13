[PRD]
# PRD: P2 — Browser hardening e `execute_code` sandboxed

## 1. Visão geral

Os PRs #14–#31 fecharam o núcleo de segurança do Donkey: approval gate, SSRF por hop no `fetch`, TLS nativo, vault AES-256-GCM, ledger durável e drill operacional. A cobertura P2 ainda tem duas lacunas relevantes:

1. o browser headless valida a URL de navegação e intercepta requests via CDP, mas não tem política explícita para redirects, WebSocket, service workers, downloads e tamanho de página/screenshot;
2. não existe uma tool de execução de código arbitrário com isolamento, timeout, cap de saída, gate de aprovação e auditoria.

Este PRD define dois épicos independentes, um PR cada, sem acoplar browser e execução de código.

## 2. Objetivos

- Provar que o browser aplica a política de URL/DNS em navegação, subrecurso, redirect e WebSocket, e que service workers/downloads não viram canal de bypass.
- Limitar recurso e tempo do browser para que uma página hostil não derrube o daemon.
- Entregar `execute_code` somente com sandbox OCI/WASI, sem rede por default, com approval gate, timeout, cap de saída e auditoria.
- Manter domínio puro: decisões de política em `domain/`; I/O em `adapters/`/`infra/`; dispatch em `app/`.
- Não quebrar contratos públicos existentes de `bash`, `fetch`, browser ou approval.

## 3. Quality Gates

Toda história deve passar:

- `bash scripts/check_boundaries.sh`
- `nimble build -y`
- `JOBS=6 bash scripts/run_tests.sh` (suíte normal)
- `bash scripts/run_stress_tests.sh` quando a história tocar concorrência/tempo
- `coderabbit review --agent --base master` sem findings válidos pendentes
- CI do GitHub Actions verde

Critérios adicionais:

- testes de bypass devem falhar fechado, não apenas “não lançar exceção”;
- nenhum teste pode depender de browser, Docker ou rede externa reais;
- limites numéricos precisam de teste de borda (zero, negativo, acima do máximo);
- toda recusa de política deve ser determinística e observável no resultado da tool.

## 4. Não-objetivos

- Não substituir o proxy/firewall de egress. DNS rebinding continua exigindo pinning de conexão no proxy; o browser só reduz a janela e falha fechado onde o CDP permite.
- Não implementar um navegador completo nem suportar downloads.
- Não executar código no host sem sandbox, nem oferecer fallback silencioso.
- Não introduzir uma segunda política de aprovação: `execute_code` usa o approval gate existente.
- Não prometer isolamento absoluto contra kernel exploit ou container escape; o objetivo é reduzir a superfície e provar os controles declarados.

## 5. Histórias de usuário

### US-001: Política pura de requests do browser

**Descrição:** Como mantenedor, quero que a decisão sobre esquema/host de navegação, subrecurso, redirect e WebSocket seja pura e testável, para que o adapter não seja a única fonte de verdade.

**Critérios de aceite:**
- [ ] `browser_pure` expõe classificação de request (`Document`, `Subresource`, `WebSocket`, `ServiceWorker`) e política de esquema.
- [ ] `http`/`https` públicos são permitidos; `file`, `chrome`, `ftp`, `ws`, `wss`, `javascript` e `filesystem` são negados.
- [ ] `data:`, `blob:` e `about:` continuam permitidos apenas como conteúdo inline, nunca como navegação.
- [ ] Testes cobrem hosts privados literais, IPv6, userinfo, porta e URL malformada.
- [ ] Nenhuma função pura importa adapter/rede/processo.

### US-002: Validação por hop no browser

**Descrição:** Como operador, quero que cada request do browser passe pela mesma política, inclusive redirects e subrecursos.

**Critérios de aceite:**
- [ ] `Fetch.requestPaused` valida a URL antes de `continueRequest`.
- [ ] Redirect para host privado é bloqueado e registrado como violação.
- [ ] Subrecurso privado é bloqueado sem derrubar a navegação inteira.
- [ ] Documento principal ou iframe para host privado aborta a navegação e fecha o browser.
- [ ] Eventos CDP são drenados também após erro, evitando request pausado eterno.
- [ ] Teste de política cobre request pausado de documento e de subrecurso.

### US-003: WebSocket, service worker e downloads fail-closed

**Descrição:** Como operador, quero que canais que não passam pelo `Fetch` não sejam usados para exfiltração.

**Critérios de aceite:**
- [ ] WebSocket é bloqueado na criação (`Network.webSocketCreated` + script injetado + `Network.setBlockedURLs` quando suportado).
- [ ] Service worker é desregistrado/bloqueado por script, `Network.setBypassServiceWorker` quando suportado e eventos `ServiceWorker.*` monitorados.
- [ ] Downloads são negados quando o CDP suportar; ausência de suporte vira warning explícito.
- [ ] Qualquer violação de WebSocket/service worker fecha o browser e retorna erro à tool.
- [ ] Testes não dependem de Chromium real; cobrem classificação e conteúdo dos scripts.

### US-004: Limites de tempo, conteúdo e screenshot

**Descrição:** Como operador, quero que uma página hostil não consuma memória/tempo sem limite.

**Critérios de aceite:**
- [ ] Timeout CDP configurável (`DONKEY_BROWSER_TIMEOUT_MS`), com default 30s e máximo 120s.
- [ ] `max_chars` é validado, limitado ao hard cap e aplicado no lado do browser antes de serializar o HTML.
- [ ] `waitUntil` só aceita `networkidle`, `load` e `domcontentloaded`.
- [ ] Screenshot acima do cap retorna erro claro em vez de base64 gigante.
- [ ] Testes cobrem zero, negativo, valor acima do cap e screenshot no limite.

### US-005: Perfil e limpeza

**Descrição:** Como operador, quero que perfis de browser não vazem cookies entre usuários nem fiquem legíveis por outros.

**Critérios de aceite:**
- [ ] Perfil criado pelo adapter usa `0700` em POSIX e é removido no close/falha.
- [ ] Perfil configurado pelo operador também é restringido a `0700`.
- [ ] Portas CDP continuam distintas por usuário e são liberadas no eviction.
- [ ] Testes verificam permissões e limpeza sem abrir browser.

### US-006: `execute_code` com sandbox OCI

**Descrição:** Como usuário, quero executar um trecho de código no workspace sem acesso à rede e sem tocar o host.

**Critérios de aceite:**
- [ ] Tool `execute_code` aceita `language` (`python`, `javascript`, `shell`) e `code`.
- [ ] Em `[sandbox] mode = "oci"`, roda com `--network=none`, rootfs read-only, `--cap-drop=ALL`, `no-new-privileges`, tmpfs limitado, limites de memória/CPU/PID e bind mount apenas do paddock.
- [ ] Não existe fallback para host; runtime ausente ou imagem indisponível retorna erro.
- [ ] Código é passado como argv, não como shell do host.
- [ ] `sandbox.mode = "none"` é recusado para `execute_code`.

### US-007: `execute_code` com sandbox WASI

**Descrição:** Como usuário, quero executar um módulo WASM no workspace sem rede.

**Critérios de aceite:**
- [ ] Em `[sandbox] mode = "wasm"`, `execute_code` aceita `language = "wasm"` e `wasm_path` dentro do paddock.
- [ ] wasmtime roda com `--dir={paddock}` e `--dir=/tmp` apenas; sem flags de rede.
- [ ] Path fora do paddock, symlink para fora e módulo inexistente falham fechado.
- [ ] Testes cobrem resolução de path e argv sem executar wasmtime.

### US-008: Gate, timeout, cap e auditoria de `execute_code`

**Descrição:** Como operador, quero que toda execução seja aprovada, limitada e auditável.

**Critérios de aceite:**
- [ ] `execute_code` está em `defaultApprovalTools` e respeita `DONKEY_APPROVAL_TOOLS`.
- [ ] Falha ao criar/consultar aprovação nega a execução (fail-closed).
- [ ] Timeout default 10s, máximo 60s, aplicado por `timeout` externo e limpeza do container.
- [ ] Saída combinada é limitada por `DONKEY_CODE_MAX_OUTPUT_BYTES` (default 64 KiB) e marcada como truncada.
- [ ] Código acima de `DONKEY_CODE_MAX_SOURCE_BYTES` é recusado antes do spawn.
- [ ] Auditoria em log estruturado contém user, tool, language, hash do código, duração, exit code, timeout/truncamento e imagem; nunca o código.
- [ ] Testes cobrem exit code, timeout, output bomb, source bomb, path traversal e ausência de runtime.

### US-009: Documentação e limites conhecidos

**Descrição:** Como operador, quero saber o que o hardening garante e o que depende de infraestrutura.

**Critérios de aceite:**
- [ ] `docs/hardening.md` documenta browser e `execute_code`.
- [ ] Limitações de DNS rebinding, service worker e downloads são explícitas.
- [ ] Variáveis de ambiente e exemplos de configuração estão documentados.
- [ ] V2 é atualizada após o merge dos dois PRs.

## 6. Sequência de entrega

1. PR A — US-001 a US-005 (browser hardening).
2. PR B — US-006 a US-008 (`execute_code`).
3. PR C — US-009 se a documentação não couber nos PRs anteriores.

Cada PR deve ser mergeável sozinho, com CI verde e sem dependência do outro.

## 7. Follow-ups registrados

- **Pinning de conexão do browser:** o `Fetch` valida a URL, mas a conexão ainda resolve DNS novamente. Proxy/firewall com pinning continua sendo a garantia forte; um teste de DNS rebinding real depende dessa infraestrutura.
- **Service workers em engines sem CDP completo:** Chromium cobre bypass + script + eventos; Lightpanda depende do script injetado e do limite de frame, com proxy/firewall como fallback.
