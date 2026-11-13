[PRD]
# PRD: Endurecimento P1 — pressão, falha e concorrência

## 1. Visão geral

Os PRs #22–#28 entregaram approval gate, SSRF por hop, TLS nativo, vault de segredos, compactação do ledger em worker e Slack Socket Mode. A validação atual cobre caminho feliz, erros previstos e revisão estática, mas não prova esses subsistemas sob concorrência, crash, I/O lento, disco cheio, rede instável e rotação de credenciais.

Este PRD define uma passada de endurecimento **sem novas features de produto**: testes de pressão e falha, correções encontradas e um runbook operacional. O objetivo é transformar “revisado” em “provado sob condições adversas” antes de retomar breadth P2.

## 2. Objetivos

- Provar que approval store, vault, ledger worker e receiver TLS não corrompem estado sob concorrência.
- Provar que o SSRF bloqueia um corpus amplo de URLs/redirects, não só os casos do PR #24.
- Provar que Socket Mode e parser WebSocket não travam o shutdown nem perdem eventos por frame parcial.
- Adicionar um harness de stress opt-in, determinístico e com tempo limitado.
- Corrigir qualquer bug encontrado, sem alterar contratos públicos existentes.
- Registrar limites conhecidos e procedimentos de recuperação em `docs/hardening.md`.

## 3. Quality Gates

Estes comandos devem passar para toda história:

- `bash scripts/check_boundaries.sh` — boundaries arquiteturais
- `nimble build -y` — build do binário
- `JOBS=6 bash scripts/run_tests.sh` — suíte normal
- `bash scripts/run_stress_tests.sh` — suíte de stress (nova)
- `coderabbit review --agent --base master` — 0 findings
- CI do GitHub Actions verde

Critérios adicionais para histórias de concorrência:

- cada teste de stress roda pelo menos 20 iterações ou 10 threads;
- nenhum teste pode depender de ordem de scheduling;
- timeout total do harness de stress ≤ 300s (execução ≤ 120s);
- falhas devem reproduzir e ser corrigidas, não marcadas como flaky.

## 4. Histórias de usuário

### US-001: Harness de stress opt-in

**Descrição:** Como mantenedor, quero uma suíte de stress separada da suíte normal para rodar pressão sem tornar o CI comum lento ou instável.

**Critérios de aceite:**
- [ ] `scripts/run_stress_tests.sh` compila e roda apenas `tests/stress/*.nim`.
- [ ] `scripts/run_tests.sh` ignora `tests/stress` por padrão e aceita `DONKEY_STRESS=1`.
- [ ] CI executa a suíte de stress após a suíte normal.
- [ ] Harness falha com exit code não-zero e imprime logs por arquivo.
- [ ] Tempo total do harness vazio/inicial < 180s no CI.

### US-002: Approval store sob concorrência

**Descrição:** Como operador, quero que criações e decisões concorrentes do approval gate não percam pedidos nem permitam decisão dupla.

**Critérios de aceite:**
- [ ] Teste com 10+ threads cria pedidos distintos e todos os IDs são únicos e listáveis.
- [ ] Teste com 10 threads decidindo o mesmo pedido resulta em exatamente um sucesso.
- [ ] Teste de cap por usuário com threads nunca ultrapassa `MaxPendingPerUser`.
- [ ] Nenhuma escrita parcial é observada por leitores concorrentes.
- [ ] Falhas encontradas são corrigidas com teste de regressão.

### US-003: Vault de segredos sob concorrência e falha

**Descrição:** Como operador, quero que `set`, `remove` e leitura do vault sejam seguros sob concorrência e falhem fechado em corrupção.

**Critérios de aceite:**
- [ ] 10+ threads gravando chaves distintas resultam em todas as chaves presentes e JSON válido.
- [ ] Leitores concorrentes nunca observam vault truncado ou plaintext.
- [ ] Teste de lote grande/valor grande permanece atômico.
- [ ] Chave substituída, ausente ou ciphertext adulterado continuam retornando erro sem escrever.
- [ ] Permissões finais permanecem `0600`/`0700` em POSIX.

### US-004: Ledger worker sob concorrência

**Descrição:** Como operador, quero compactar o ledger enquanto entregas são registradas sem perder registros pendentes ou corromper o arquivo.

**Critérios de aceite:**
- [ ] 4+ threads registram e finalizam centenas de entregas enquanto o worker compacta.
- [ ] Nenhum `loadAll` retorna erro; todos os registros recentes permanecem.
- [ ] Registros pendentes são preservados mesmo quando antigos.
- [ ] `stopLedgerCompactionWorker` é idempotente e retorna em < 2s.
- [ ] Teste cobre stop durante compactação sem deadlock.

### US-005: Corpus SSRF

**Descrição:** Como mantenedor, quero um corpus de URLs e redirects maliciosos para impedir regressões no controle de SSRF.

**Critérios de aceite:**
- [ ] Corpus puro cobre userinfo, `@` em path/query, IPv6, IPv4 mapeado, loopback, link-local, faixas privadas e URLs públicas.
- [ ] Corpus de redirect cobre 5 hops, excesso, loop, `Location` relativo, ausência de `Location`, DNS privado e porta sem `getNoRedirect`.
- [ ] Cada vetor privado é bloqueado antes da requisição.
- [ ] URLs públicas legítimas continuam aceitas.
- [ ] Nenhuma regressão no teste existente de `t_structured_web_tools`.

### US-006: TLS do webhook sob pressão

**Descrição:** Como operador, quero que o receiver TLS suporte conexões e restarts repetidos sem vazar worker ou travar shutdown.

**Critérios de aceite:**
- [ ] 20 handshakes TLS sequenciais respondem ao challenge assinado.
- [ ] 5 ciclos start/stop com TLS terminam sem erro e sem double free.
- [ ] Shutdown com cliente TLS lento retorna em < 10s.
- [ ] Certificado inválido/rotação continua falhando fechado.
- [ ] Teste é skip limpo quando `openssl` não está disponível.

### US-007: Socket Mode e parser WebSocket sob fuzz

**Descrição:** Como mantenedor, quero que envelopes malformados e frames parciais não derrubem o daemon nem causem perda silenciosa.

**Critérios de aceite:**
- [ ] Envelopes nil, array, string, sem payload, payload inválido e tipos desconhecidos não lançam exceção.
- [ ] `events_api`, `slash_commands` e `interactive` válidos continuam enfileirando eventos.
- [ ] Frame WebSocket válido é parseado; frame truncado gera erro de protocolo/reconexão, não `TimeoutError` de idle.
- [ ] `disconnect` sinaliza reconexão.
- [ ] Teste cobre `interactive` com payload string e objeto.

### US-008: Runbook de hardening

**Descrição:** Como operador, quero um documento com a matriz de stress, como rodar, limites conhecidos e recuperação de falhas.

**Critérios de aceite:**
- [ ] `docs/hardening.md` lista comandos e tempo esperado.
- [ ] Documenta os limites: pinning de egress, backup da chave, at-most-once do Socket Mode, compactação de startup.
- [ ] Inclui procedimentos para vault corrompido/chave perdida, ledger corrompido e receiver TLS inválido.
- [ ] Inclui a política de rodar stress antes de releases e após mudanças em locks/cripto/TLS.

### US-009: Validação final e PR

**Descrição:** Como mantenedor, quero fechar a passada de hardening com suíte normal, stress, boundaries, build, CodeRabbit e CI verdes.

**Critérios de aceite:**
- [ ] Suíte normal: 0 falhas.
- [ ] Suíte de stress: 0 falhas e dentro do tempo.
- [ ] Build e boundaries verdes.
- [ ] CodeRabbit 0 findings.
- [ ] PR descreve achados, correções e limitações.

## 5. Requisitos funcionais

- FR-1: O harness de stress deve ser opt-in e não alterar a suíte normal.
- FR-2: Testes de concorrência devem usar threads do Nim e coletores protegidos, sem sleeps para sincronizar resultados.
- FR-3: Testes de falha de I/O devem usar diretórios temporários isolados e limpeza `defer`.
- FR-4: Nenhum teste pode depender de rede externa; TLS pode gerar certificado local via `openssl`.
- FR-5: Correções devem preservar as interfaces públicas existentes de `ApprovalStore`, `SecretVault`, `RuntimeStateStore`, `WebhookReceiver` e `HttpRuntimePort`.
- FR-6: O CI deve executar stress em todo PR.
- FR-7: Logs de falha devem identificar arquivo e teste.

## 6. Não-objetivos

- Novas features de produto, canais ou providers.
- Pinning completo de conexão do SSRF (continua dependendo de proxy/firewall).
- ACME/renovação automática de certificados.
- Lease/WAL/resume transacional do ledger.
- Refactor arquitetural amplo ou reescrita.
- Testes de carga com ferramentas externas (`wrk`, `hey`) no CI.
- Cobertura de 100%; foco em risco.

## 7. Considerações técnicas

- `flock` no approval store/vault é por descritor aberto; threads com `open` separado devem serializar no Linux.
- O vault já usa `Result`; correções não devem reintroduzir `raise` em adapters.
- O worker do ledger usa `Lock` do store; stress deve concorrer com appends reais.
- TLS de teste deve gerar certificado self-signed com SAN `localhost`/`127.0.0.1`.
- WebSocket de teste pode usar `socketpair(AF_UNIX)` e frames crus, sem servidor de rede.
- Testes de stress devem ser compilados com `--mm:orc` e `-d:release` quando seguro; se `-d:release` ocultar checagens, usar build normal.

## 8. Métricas de sucesso

- 0 falhas no harness de stress em 10 execuções consecutivas locais.
- Nenhum deadlock ou timeout > 300s no harness.
- Nenhuma perda de pedido/decisão/entrega nos cenários testados.
- Corpus SSRF com 100% dos vetores privados bloqueados.
- CI normal continua abaixo de ~8 min; stress adiciona ≤ 2 min.
- CodeRabbit 0 findings no PR final.

## 9. Questões em aberto

- Rodar stress em todo PR ou apenas nightly? Decisão inicial: todo PR, com tempo limitado; migrar para nightly se passar de 2 min.
- Incluir `-d:release` no stress? Decisão inicial: não, para manter checks/panics.
- Cobrir DNS rebinding real? Não neste PR; simular via mock de `resolveHost`.
[/PRD]
