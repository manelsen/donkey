# TODO — Donkey

Itens concretos em aberto, ordenados por urgência dentro de cada categoria. Para roadmap de fases, ver `ROADMAP.md`.

---

## F3 — Function calling e streaming (providers pendentes)

- [ ] **Anthropic function calling**: `buildBody` ignora `req.tools`; precisa serializar como `tools:[{name,description,input_schema}]` e parsear `tool_use` blocks na resposta; histórico usa `tool_result` content blocks (não `role=="tool"`).
- [ ] **Gemini function calling**: `buildBody` ignora `req.tools`; precisa de `tools:[{functionDeclarations:[...]}]`; resposta tem `functionCall` part; `requiresUserFirst=true` — normalizar histórico (function response não pode seguir user turn).
- [ ] **Anthropic/Gemini `caps()` correction**: enquanto não implementado, `toolCalling` deveria ser `false` para não enganar o orchestrator.
- [ ] **OpenRouter SSE streaming**: `makeStreamFn` é fallback não-streaming ("emit full text as one token"). Implementar SSE real com `data: [DONE]` detection.
- [ ] **Anthropic streaming**: `streaming: true` nas `caps()` mas não implementado — `content_block_delta` events.

## Tools / Native tools

- [ ] **`grep` com regex**: regex literal não funciona (libpcre.so.3 ausente em algumas distros). Opções: (a) usar `re` de Nim com PCRE bundled, (b) implementar subset básico de regex sem PCRE, (c) exigir instalação do pacote e documentar.
- [ ] **Validação de permissions em `saveSkillEntry`**: bloquear `--allow-all` e `--allow-run` sem confirmação explícita do operador; exigir targets concretos em `--allow-net`/`--allow-read`.
- [ ] **Docker sandbox integration test**: `smDocker` tests em `t_sandbox.nim` marcados como skip — adicionar quando Docker disponível no CI.

## Memória

- [ ] **`.md` como views/exports do grafo** (F6+): gerados sob demanda via `donkey ctl memory export <user>` ou automaticamente pelo daemon a cada sessão fechada.

## Channels

- [ ] **`WeChatAdapter`** (F8): Official Account API, OAuth 2.0, template messages.
- [ ] **`QQAdapter`** (F8): OneBot protocol — definir v11 vs v12.

## CLI / TUI

- [ ] **`donkey ctl` consolidado** (pós-F9): todos os comandos F1-F8 num único help. Atualmente comandos definidos em módulos separados sem entry point unificado.
- [ ] **User manager panel** (pós-F9): painel TUI para listar usuários, editar perfil, revogar acesso.

## Segurança

- [ ] **Prompt injection via tool output**: sem solução técnica completa disponível. Documentado em CLAUDE.md (Threat model). Mitigações a considerar: prefixar todo tool output com marcador não-instrução, separar em content blocks distintos se o provider suportar.

## Decisões abertas

- [ ] **F6:** `.md` como views do grafo — geradas automaticamente pelo daemon ao fechar sessão, ou exportadas sob demanda via `donkey ctl memory export <user>`? (Decisão de F6, não urgente.)
- [ ] **F8:** QQ — OneBot v11/v12 ou API oficial?

### Fechadas (não remover — histórico)

- ~~**F2 manifesto de skill**~~ → `SkillManifest` como struct Nim em `skills.toml [[skill]]`. Clawhub integration é problema de F7, não de formato.
- ~~**F4 workers persistentes vs. on-demand**~~ → On-demand: `asyncSpawn` fire-and-forget por sessão (ver orchestrator.nim).
- ~~**F1 long polling vs webhook**~~ → Config: `[telegram] webhook_url` presente → webhook; ausente → long polling. (Webhook não implementado ainda — ver TODO acima.)

---

## Config / Secrets

- [ ] **Long polling vs webhook**: `TelegramAdapter` usa long polling. Adicionar modo webhook (flag ou auto-detect por URL configurada). Decisão: config `[telegram] webhook_url` presente → webhook; ausente → long polling.

## Feito recentemente (não mergear de volta)

- ✅ Function calling OpenRouter + Zhipu (tools array + tool_calls parsing)
- ✅ Paddock por usuário + path enforcement (`resolveInPaddock`, `inPaddock`)
- ✅ Symlinks ignorados em find/grep
- ✅ Detecção de repetição substituindo MaxToolRoundsOrch=5
- ✅ Progress embed (isPartial streaming durante tool loop)
- ✅ Docker sandbox (`sandbox.nim`, `smNone`/`smDocker`, `[sandbox]` em config)
- ✅ Suite completa de testes native tools (70+ testes)
- ✅ Faxina de warnings do compilador
- ✅ `donkey service install/remove/start/stop/restart/logs` — systemd --user, sem root
- ✅ `deploy/` — unit file, env.example, toml.example, install.sh standalone
