# TODO — Donkey

Itens realmente abertos no estado atual do código. Para visão por fases, ver [`ROADMAP.md`](/home/micelio/git/donkey/ROADMAP.md). Para histórico do refactor-base, ver [`REFACTOR_PLAN.md`](/home/micelio/git/donkey/REFACTOR_PLAN.md).

---

## P0 — Hardening imediato

- [ ] **Prompt injection via tool output**
  Estado:
  o runtime ainda trata tool output como texto comum no histórico.
  Próximo passo:
  prefixar output de tools com marcador não-instrucional e separar melhor erro operacional de resultado funcional.

- [ ] **`grep` com regex sem dependência frágil de PCRE**
  Estado:
  o comportamento ainda pode variar por distro.
  Próximo passo:
  padronizar engine suportada ou documentar explicitamente o subset aceito.

- [ ] **Trocar `std/sha1` deprecated no `WeChatAdapter`**
  Estado:
  a validação de assinatura compila e funciona, mas usa módulo deprecated.
  Próximo passo:
  migrar para `checksums/sha1` ou equivalente não deprecated.

---

## F7 — Skills ecosystem

- [ ] **Bundles remotos executáveis além do modo “skill de instrução”**
  Estado:
  bundles remotos do ClawHub já entram no runtime da sessão como skill prompt (`SKILL.md` instalado é injetado no system prompt e participa do rebuild de sessão), mas ainda não viram MCP/Deno skills executáveis automaticamente.

- [ ] **Hardening de permissões em skills**
  Estado:
  continua faltando validar/bloquear permissões perigosas demais em `saveSkillEntry`.

---

## F8 — Canais chineses

- [ ] **Ingress real de WeChat**
  Estado:
  `WeChatAdapter` já cobre OAuth URL, parsing de webhook XML, envio e template message, mas o inbound ainda depende de forwarding externo para `enqueueWebhookXml`.

- [ ] **Ingress real de QQ / OneBot**
  Estado:
  `QQAdapter` já cobre send e parsing de evento, mas ainda depende de forwarding externo para `enqueueEventJson`.

- [ ] **Fixtures/end-to-end dos canais novos**
  Estado:
  há testes unitários de parse/roteamento, mas não há smoke e2e dos fluxos completos de inbound/outbound nesses canais.

---

## F9+ — Admin / operação

- [ ] **Persistir e expor estado administrativo mais rico no IPC**
  Estado:
  o TUI já mostra usuários locais e o CLI já edita/revoga, mas o daemon ainda não expõe um modelo administrativo mais rico via IPC.

- [ ] **Ações administrativas interativas no TUI**
  Estado:
  o painel de usuários existe, mas edição/revogação ainda ficam no `ctl`.

---

## CI / infraestrutura

- [ ] **Docker sandbox integration test**
  Estado:
  `smDocker` continua sem cobertura automática porque o ambiente de teste nem sempre tem Docker disponível.

- [ ] **Cobertura de Postgres com banco real em CI**
  Estado:
  a parte `withPostgres` compila e tem testes, mas parte da validação ainda é compile-only quando não há socket/banco disponível.

---

## Feito recentemente

- ✅ F3 fechado: function calling real em Anthropic/Gemini e streaming real em OpenRouter/Anthropic
- ✅ F6 fechado: `ctl memory export` e views textuais sobre Postgres
- ✅ F7 fechado no CLI: search/install/update remotos do ClawHub com lock/origin/hash
- ✅ F8 fechado no runtime base: `WeChatAdapter` e `QQAdapter` integrados ao daemon/outbound
- ✅ F9 fechado no runtime base: painel de usuários no TUI, `ctl user edit/revoke/allow`, bloqueio de usuário revogado no ingresso
- ✅ Refactor-base concluído: daemon, orchestrator, bootstrap, outbound, loaders e native tools fatiados e cobertos
