[PRD]
# PRD: Breadth de canais — LINE de ponta a ponta e ingress webhook compartilhado

> **Executor:** agente autônomo. Leia tudo antes de começar e execute as histórias
> **na ordem**. Cada história termina com os quality gates verdes e um commit
> próprio. Não abra a seguinte com a anterior vermelha.

## 1. Contexto

A V4 (`COBERTURA_HERMES_VS_DONKEY_V4.md`, §6, prioridade 5) mede Canais em 75%
com breadth parado em 13 adapters. O recorte é **um** canal novo de ponta a ponta.
Hoje cada webhook reimplementa o mesmo caminho em
`adapters/webhook/webhook_receiver.nim`: método, segredo, janela de replay, JSON,
challenge e `pushEvent` — cinco variações de ~40 linhas com HMAC e comparação
constante duplicados; um sexto canal copiaria a sexta.

| Canal | Auth de entrada | Payload | Saída | SDK |
|---|---|---|---|---|
| Google Chat | JWT OIDC + JWKS remoto | JSON aninhado | OAuth service account | não |
| Microsoft Teams | JWT Bot Framework + JWKS remoto | `activity` | token AAD + Connector | não |
| **LINE** | **HMAC-SHA256 base64 do corpo bruto** | **`events[]` plano** | **Bearer estático** | **não** |
| IRC | nenhuma (socket TCP) | texto de protocolo | nenhuma | não |
| SMS (Twilio) | HMAC-SHA1 sobre URL + form | form-encoded | Basic auth | não |

**Escolha: LINE.** É o único candidato em que a entrada inteira é função pura do
corpo e de um segredo estático, e a saída é um POST com Bearer estático e
`apiBase` sobrescrevível — a opção mais barata de verificar, e o par certo para o
ingress: MAC de corpo (LINE) + MAC de timestamp (DingTalk).

**Protocolo** (`/home/micelio/git/hermes-agent`, read-only; `adapter.py` =
`plugins/platforms/line/adapter.py`, `line.md` = `website/docs/user-guide/messaging/line.md`):

- **Assinatura:** `X-Line-Signature` = base64(HMAC-SHA256(secret, corpo bruto)),
  comparação constante; segredo vazio rejeita — `adapter.py:138-147,508-509`;
  teste `tests/gateway/test_line_plugin.py:55-68`.
- **Payload:** `{"events":[…]}` com `type`, `mode` (`active`/`standby`),
  `webhookEventId`, `deliveryContext.isRedelivery` (LINE OpenAPI `webhook.yml`;
  o Hermes não lê esse campo), `replyToken`,
  `source{type,userId,groupId,roomId}` e `message{type,id,text}` —
  `adapter.py:514-567,200-209`.
- **Saída e destino:** reply (`/v2/bot/message/reply`, token único ~60 s) e push
  (`/v2/bot/message/push`); o `to` do push é sempre o **id cru** `U…`/`C…`/`R…`,
  nunca prefixado — Hermes envia o id de `source` (`adapter.py:247-248,548-551,890`).
- **Limites:** 5000 chars por bolha, chunk em 4500, ≤5 bolhas por chamada —
  `adapter.py:58-60,117-135,283`; `line.md:198`.
- **Dedupe:** por `webhookEventId`, bound 1000 e sem TTL no Hermes
  (`adapter.py:420-421,524-527`; `gateway/platforms/helpers.py:28-52`). A
  documentação da LINE declara redelivery opt-in e não publica
  contagem/intervalo; o Hermes assume "até 1 dia" num comentário — usamos 24 h
  como margem conservadora.
- **Webhook:** corpo ≤1 MiB, `401` sem assinatura e `200 "ok"` no sucesso
  (`adapter.py:62,499-519`); o botão "Verify" do console posta `events: []` e
  exige `200`. `mode == "standby"` significa "outro módulo responde"; o Hermes
  não lê `mode` — nós não respondemos (desvio deliberado, `line.md`/API ref).

## 2. Objetivos

1. LINE inbound e outbound com `Result` em toda borda, sem `raise` fora de adapter e sem SDK.
2. Ingress **compartilhado** (`webhook_ingress.nim`) usado por LINE e DingTalk, sem mudar comportamento observável.
3. Parsing/política puros em `domain/channels/`; HTTP, fila e wiring só em app/adapter.

## 3. Fora de escopo

- Migrar Slack, Feishu, Matrix e WhatsApp para o helper; qualquer auth hex/shared-token.
- Reply token, mídia, botões, quick reply, broadcast, LIFF, rich menus, edição; providers, memória, roteamento e dashboard.

## 4. Quality gates

Obrigatórios ao fim de **toda** história: `bash scripts/check_boundaries.sh`,
`nimble build -y`, `JOBS=6 bash scripts/run_tests.sh`, `git diff --check`.

Regras adicionais, sem exceção:

- TDD: teste primeiro, falha mostrada, implementação mínima, verde.
- Lógica pura em `domain/` como `func`; o adapter só faz ligação HTTP/fila.
- Proibido `raise` fora de adapter; I/O falível devolve `Result[T, string]`.
- Nenhum teste novo usa rede, conta LINE real ou Docker (`apiBase` sempre sobrescrito), e nenhum teste existente é editado.
- Se o worktree estiver sujo ao começar, **pare** e registre.

### 4.1 Ciclo de execução — TDD não é opcional

Por história: escrever **um** teste e rodá-lo; mostrar a falha (módulo/símbolo
ausente ou asserção) no relato; implementar o mínimo; rodar o teste até verde,
os gates e commitar com o vermelho → verde no corpo. Teste que passa antes da
implementação está errado.

### 4.2 Ordem e ownership

- Ordem fixa: US-000 → US-001 → US-002 → US-003 → US-004 → US-005 → US-006 → US-007. Nada em paralelo.
- `src/donkey.nim` tem um único escritor por vez (US-000 só o branch de `outboundPortForChannel`; US-005/US-006 o resto, serializadas); `app/outbound_runtime.nim` não roda com durabilidade; `ports/channel_capability.nim` não roda com ferramentas (`cfSendVoice`). Suíte completa e commits são sequenciais.

## 5. Preparação (antes da US-000)

Com worktree limpo: `git fetch origin && git switch master && git pull --ff-only`,
criar `feat/channel-line` e registrar no commit de abertura que este PRD é a fonte
de verdade. `git status --short` sujo → **pare**.

## 6. Histórias

### US-000: Enum, capability e pairing (serializada)

**Descrição:** o canal precisa existir para o compilador antes de qualquer LINE.

**Critérios de aceite:**
- [ ] `ChannelKind` ganha `ckLine` ao fim do enum e `$ckLine == "line"` (`core/types.nim`); `ports/channel.nim` ganha `OutboundChannelPorts.line`.
- [ ] `ports/channel_capability.nim`: `LineCapability` (`send: true`, demais `false`) e entrada no `channelCapabilityRegistry`.
- [ ] `app/outbound_runtime.nim`: todos os `case` exaustivos ganham `ckLine` — `channelTag` (`"ln"`), `channelPortFor`, reação e log de edit/send; `outboundPortForChannel` em `src/donkey.nim:1360-1372` ganha `of ckLine: ports.line` (US-000 só toca esse branch).
- [ ] `adapters/state/pairing_store.nim`: `parseChannelName` aceita `"line"`; teste novo `tests/adapters/state/t_pairing_line.nim` prova round-trip save/load.
- [ ] `tests/ports/t_channel_capability.nim` e `t_outbound_builder_caps.nim` passam **sem edição** (ambos exigem `send` para todo `ChannelKind`); novo `tests/ports/t_line_capability.nim` prova `send = true` e `sendReturnId`/`editMessage`/`sendKeyboard`/`editKeyboard`/`setMessageReaction`/`downloadFile`/`sendMedia` falsos.

### US-001: Parsing puro do webhook LINE

**Descrição:** payload vira resultado puro, com fonte e conteúdo separados.

**Critérios de aceite:**
- [ ] Criar `src/donkey/domain/channels/line_pure.nim` com `LineSourceKind` (`lskUser`, `lskGroup`, `lskRoom`, `lskUnknown`), `LineContentKind` (`lckText`, `lckNonText`, `lckUnknown`), `LineMode` (`lmActive`, `lmStandby`) e `LineParseResult` (`senderId`, `chatId`, `sourceKind`, `contentKind`, `mode`, `isRedelivery`, `text`, `messageId`, `eventId`, `replyToken`); `parseWebhook*(payload: JsonNode): seq[LineParseResult]`; `toInbound*(r, userId): InboundMessage` preenche `channel = ckLine`, `rawChannelId = senderId`, `channelId = chatId`, `chatId = chatId`, `isGroup = sourceKind != lskUser`.
- [ ] Precedência: `sourceKind` e `contentKind` são ortogonais; em grupo/room `senderId = source.userId` e `chatId = groupId/roomId`; em DM ambos são `userId`; `message.type != "text"` → `lckNonText`; `type != "message"` → `lckUnknown`; `mode == "standby"` é preservado; `deliveryContext.isRedelivery` é lido só para telemetria (nunca decide descarte); payload que não é `JObject` ou sem `events` array → `@[]` (JSON malformado vira 400 em US-005 e nunca chega ao parser); `events` vazio → `@[]` (Verify do console).
- [ ] Teste em `tests/domain/channels/t_line_pure.nim` com `tests/fixtures/line/webhook_text.json`, `webhook_group_text.json`, `webhook_standby.json`, `webhook_non_message.json` e `webhook_empty_events.json`; grupo+sticker prova `lskGroup`+`lckNonText`.

### US-002: Política inbound pura (replay, gates e roteamento)

**Descrição:** decisões puras que o runtime consome; assinatura não mora aqui.

**Critérios de aceite:**
- [ ] Criar `src/donkey/domain/channels/line_policy.nim` (não editar `line_pure.nim`) com `LineReplayCache`, `replayDecision*(cache; eventId; nowSec): bool`, `recordEvent*(cache: var LineReplayCache; eventId; nowSec)` (`proc` mutador) e `replayCacheLen*`; `LinePolicy` (`allowedGroups`, `allowedUsers`), `LineEventDecision`, `decideLineEvent*`, `lineGroupAllowed*` (**default-deny**: lista vazia nega grupo/room) e `lineUserAllowed*`; `LineRouting`/`lineRouting*` (`identityId`, `replyTarget`) e a constante `LineSignatureHeader*`.
- [ ] **Sem MAC neste arquivo:** não definir `verifyLineSignature`, `lineSignatureFor` nem `constantTimeEquals`, e não importar `hmac`/`base64`; a única verificação é `decideIngress` em US-003. Se a implementação atual tiver esses símbolos, esta história os remove.
- [ ] Precedência de `decideLineEvent`: `standby` > conteúdo desconhecido/não-texto > source inválido > grupo/room não permitido > usuário não permitido > aceite; matching exato (nada de prefixo); `eventId` vazio nunca é duplicata e nunca entra no cache; TTL `86400` e bound `1000`, evicção da mais antiga.
- [ ] Teste em `tests/domain/channels/t_line_policy.nim`: decisão pura sem mutação, aceite/duplicata, TTL 24 h, evicção no limite, **allowlist exata** (`C1` vs `C1x`, `U1` vs `U10`), **dois gates falhando** (grupo e usuário) → `ledDropGroupNotAllowed`, **clock rollback** (registro no futuro continua duplicata), **duplicata no limite de evicção** e `eventId` vazio. Assinatura/KAT pertencem a US-003, não a este arquivo.

### US-003: Ingress webhook compartilhado + migração do DingTalk

**Descrição:** um MAC, um verificador, sem ciclo de import.

**Critérios de aceite:**
- [ ] Criar `src/donkey/core/security/webhook_auth.nim` (puro) com **as únicas definições** de `safeEquals*`, `hmacSha256Hex*` e `hmacSha256Base64*`; `src/donkey/adapters/webhook/webhook_ingress.nim` importa e re-exporta esse módulo, e move `WebhookRequest`, `header` e `hasQuery` para si; `webhook_receiver.nim` importa e re-exporta `webhook_ingress`. `rg "webhook_receiver" .../webhook_ingress.nim` vazio (sem ciclo) e `rg -n "func safeEquals|func hmacSha256" src` só acha o módulo core.
- [ ] `WebhookAuthSpec` com `scheme` (só `wasHmacSha256Base64`), `signedPayload` (`wspBody` \| `wspTimestampNewlineSecret`), `secret`, `signatureHeader`, `timestampHeader`, `replayWindowSec`, `timestampScale`; `decideIngress*(spec, req): WebhookIngressOutcome` (`wioAccepted`, `wioForbidden`, `wioMethodNotAllowed`, `wioNotConfigured`).
- [ ] `handleDingTalk` compõe `decideIngress(signedPayload = wspTimestampNewlineSecret)` + `parsePayload` + `pushEvent`; o MAC usa `hmacSha256Base64` do módulo core; janela ±3.600.000 ms e respostas 403/400/405/404 idênticas; `t_webhook_receiver.nim` passa **sem edição**.
- [ ] KAT e suíte de assinatura em `tests/adapters/webhook/t_webhook_ingress.nim`: corpo `{"events":[]}` + segredo `test-channel-secret` → `sKRrt+MTE71nWWZPaYrvYSdH9JGlgckmBidZxDuPgPc=`; segredo vazio → `wioNotConfigured`; timestamp fora da janela antes do MAC; método ≠ POST.

### US-004: Adapter LINE (outbound + fila)

**Descrição:** enfileirar o parse e enviar com alvo LINE correto, sem rede nos testes.

**Critérios de aceite:**
- [ ] Criar `src/donkey/adapters/channel/line.nim` com `LineAdapter` (`channelAccessToken`, `apiBase`, `resolver`, `http`), fila `Channel[LineParseResult]` (sem `LineEvent` paralelo), `pushEvent*`, `tryRecvEvent*`, `openQueue*`, `ack*` no-op e `downloadFile*` → `err("LINE: media unsupported")`.
- [ ] `lineTarget*(rawId): string` remove prefixos internos `group:`/`room:`/`user:`; `send*` usa `msg.replyTo` quando presente, senão `reverseChannel`, e envia `to = lineTarget(target)` — nunca `group:C…` (Hermes envia o id de `source`, `adapter.py:247-248,548-551`).
- [ ] `POST {apiBase}/v2/bot/message/push` com `{"to": target, "messages":[{"type":"text","text": chunk}]}`, Bearer, chunk 4500, hard cap 5000, ≤5 bolhas, excedente `"…"`; `buildPushBody*`, `buildPushUrl*`, `newLineAdapter*`.
- [ ] Teste em `tests/channel/t_line.nim`: `lineTarget("group:C1") == "C1"`, `lineTarget("U1") == "U1"`, corpo com `to` cru, 12k → 3 bolhas, >5 truncado, token ausente → `err`, fila recebe `webhook_text.json`.

### US-005: Rota `/webhook/line` e env

**Descrição:** a rota só existe com segredo; o Verify do console responde 200.

**Critérios de aceite:**
- [ ] `WebhookConfig` ganha `lineChannelSecret`; `LinePath = "/webhook/line"`; `anyRouteConfigured` inclui LINE; `handleWebhookRequest` despacha a rota.
- [ ] `handleLine` usa `decideIngress(wasHmacSha256Base64, wspBody, signatureHeader = LineSignatureHeader, sem timestamp)` (constante de `line_policy`, sem literal `"x-line-signature"`); sucesso faz `parseWebhook(payload)` → `pushEvent` → `plainResp(200, "ok")`; `{"events":[]}` também responde `200 "ok"` sem enfileirar.
- [ ] Segredo vazio → 404; assinatura inválida → 403 (Hermes 401; a LINE só exige não-2xx); JSON inválido → 400; método ≠ POST → 405.
- [ ] Teste em `tests/adapters/webhook/t_line_webhook.nim` com assinatura real e `webhook_text.json` + `webhook_empty_events.json`.
- [ ] `src/donkey.nim` (`DaemonEnv.lineAllowedGroups`/`lineAllowedUsers`, `loadDaemonEnv`, `startOptionalWebhookReceiver`) lê `LINE_CHANNEL_SECRET`, `LINE_CHANNEL_ACCESS_TOKEN` (`plugin.yaml:18-28`), `LINE_ALLOWED_GROUPS` (`plugin.yaml:46-49`; vazio = nenhum grupo, `decideLineEvent`) e `LINE_ALLOWED_USERS` (`plugin.yaml:42-45`; vazio = todos); segredo só é montado quando o token existe.

### US-006: Runtime inbound, gate por canal e wiring

**Descrição:** DM/grupo decididos antes de sessão, e o canal realmente ligado no daemon.

**Critérios de aceite:**
- [ ] Criar `src/donkey/adapters/channel/line_runtime.nim` com `drainLineEvents*(..., nowSec: int64)` consumindo a política de US-002: `decideLineEvent(LinePolicy(allowedGroups: env.lineAllowedGroups, allowedUsers: env.lineAllowedUsers), event)`; só `ledAccept` segue; `lineRouting(event)` fornece `identityId` (para `authorizeInbound(sm, gate, ckLine, routing.identityId, text, isGroup = false)`) e `replyTarget` (registrado como `chatId` em `sm.recordChannel`); `toInbound(event, userId)` monta a mensagem. Nenhuma reimplementação local de standby/conteúdo/grupo/usuário.
- [ ] Dedupe com `replayDecision(runtime.lineReplay, event.eventId, nowSec)` e `recordEvent(runtime.lineReplay, ...)` no aceite; `LineReplayCache` é value type cujo `recordEvent` reconstrói `entries` — US-006 mantém **um único `var lineReplay`** em `DaemonRuntime` e nunca copia por valor (cópia faz o dedupe virar no-op); `replayCacheLen` no log de debug.
- [ ] Intercepta **apenas** `/continue` (reuso de `lcaContinueLink`); qualquer outro texto cai em `handleSessionFallback`; evento negado é consumido e logado.
- [ ] Wiring completo: `app/gateway_drainer.nim` (campo `drainLine`, param em `initGatewayDrainer`, proc `drainLineGateway`, chamada em `drainGatewayEvents`); `DaemonAdapters.ln` + `initDaemonAdapters`; `buildOutboundPorts` + `buildRuntimeOutboundPorts`; closure de drain em `src/donkey.nim`; `LineReplayCache` no `DaemonRuntime`; `sessionReplyTo` devolve `chatId` para `ckLine`.
- [ ] Teste em `tests/adapters/channel/t_line_runtime.nim`: lista de grupos vazia nega; `C1` aceita; `C1x` nega; dois speakers do mesmo grupo recebem **identidades distintas** e ambos respondem em `chatId`; `lineRouting` e `toInbound` concordam; duplicata não gera turno; `/continue` é local e `/help` chega ao fallback; `t_dm_gate_runtimes.nim` passa sem edição.

### US-007: Docs, rollout e prova de não-duplicação

**Descrição:** a próxima pessoa adiciona um canal webhook sem copiar `webhook_receiver.nim`.

**Critérios de aceite:**
- [ ] `docs/topics/channels.md` ganha linha e seção LINE: env vars, URL pública HTTPS, passos no console (webhook + "Verify"), toggle de redelivery, `mode` standby, limites e como desabilitar.
- [ ] `rg -n "func safeEquals|func hmacSha256|proc hmacSha256" src` só encontra `core/security/webhook_auth.nim`; `rg -n "hmac|base64" src/donkey/domain/channels/line_policy.nim` e `rg -n "x-line-signature" src/donkey/adapters` vazios; `rg "pushEvent\\(payload\\)"` mostra LINE e DingTalk no mesmo caminho de `webhook_ingress`.
- [ ] Commit registra que o placar de Canais não muda (breadth +1, sem recontagem).

## 7. Requisitos funcionais

- **FR-1:** Corpo bruto é a única entrada de assinatura; segredo só é desembrulhado no adapter e o domínio recebe strings/`Result`.
- **FR-2:** `line_pure.nim` e `line_policy.nim` não importam `http`, `chronos`, `app/` nem `adapters/`; o ingress não importa o receiver; `WebhookRequest`/`header` têm um único dono (`webhook_ingress`) e `safeEquals`/`hmacSha256*` têm um único dono (`core/security/webhook_auth`).
- **FR-3:** Todo erro de envio LINE é `Result.err` com status e corpo truncado.
- **FR-4:** Gate de grupo e dedupe rodam antes de `handleSessionFallback`, mint e pairing; standby nunca responde.
- **FR-5:** O `to` do push é sempre `U…`/`C…`/`R…`; prefixos internos nunca vazam para a API.

## 8. Não-objetivos

- Unificar o receiver inteiro ou mover `WebhookResponse`/config para `core`.
- Reply token, multicast, narrowcast, botões, imagem, áudio, vídeo, stickers; persistir o cache de dedupe; reescrever Slack/Feishu/Matrix/WhatsApp.

## 9. Considerações técnicas

- **Segurança:** não há timestamp assinado (só `X-Line-Signature`, via `LineSignatureHeader`); a defesa é assinatura + dedupe de `webhookEventId` com TTL de 24 h e bound 1000. `isRedelivery` é telemetria, não defesa: um corpo capturado reenvia com o mesmo flag. MAC e comparação existem **só** em `core/security/webhook_auth` (`hmacSha256*`/`safeEquals`), re-exportados por `webhook_ingress`; `line_policy` não define MAC.
- Grupos são **default-deny** por `LINE_ALLOWED_GROUPS`, independente do `GroupGate` do Telegram; cada falante tem identidade própria (`senderId`), e o destino de saída é `chatId` via `replyTo`.
- Fila por módulo segue Feishu/DingTalk; `openQueue` uma vez no startup. `ckLine` é aditivo: `parseChannelName`, capability e `case` exaustivos são o checklist de compilação; toda função pura nova é `func`, mutação de cache é `proc` e adapters usam `try/except` só na borda.

## 10. Métricas de sucesso

- Adicionar LINE = 1 entrada de enum/capability + 1 parser + 1 política + 1 adapter + wiring; **1 definição** de `safeEquals`/`hmacSha256*` (core) e 0 cópias em adapters/domain; `line_policy` sem `hmac`/`base64`.
- `t_webhook_receiver.nim`, `t_channel_capability.nim` e `t_outbound_builder_caps.nim` verdes **sem edição**; suíte total verde (baseline 242+), sem edição de testes.
- `check_boundaries.sh` exit 0; zero import de `adapters/` em `domain/`; 0 `raise` novo fora de `adapters/`.

## 11. Questões em aberto

- **Bloqueia US-006:** `LINE_ALLOWED_GROUPS` vazio nega grupos — confirmar com o mantenedor que esse default (em vez de herdar o `GroupGate` global) é o desejado para LINE. Contagem/intervalo oficiais de redelivery não são públicos; 24 h é margem assumida e deve ser revista se a LINE mudar o opt-in. Saídas proativas sem `replyTo` caem no DM do falante (`senderId`), não no grupo.
- `/continue` apenas: se o mantenedor quiser `/whoami`, `/help` e `/link` locais, vira PRD de comandos por canal.
[/PRD]
