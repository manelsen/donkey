# Casos — mineração do WhatsApp (Cloud API)

Mesma regra do Telegram e do Discord: transfere-se o comportamento da API
documentado nos commits do hermes, não o código. Atribuição MIT em
`THIRD_PARTY_NOTICES.md`.

## Corpus

- `HERMES_REF`: `HEAD` do hermes nesta rodada (SHA completo em `LAST_SYNC`).
- Extração: `HERMES_REF=HEAD bash scripts/hermes_mine.sh whatsapp`; duas
  execuções produzem `commits.tsv` byte-idêntico.
- **225 commits** (assuntos `fix.*whatsapp` unidos aos fixes que tocam
  `plugins/platforms/whatsapp_cloud`, `plugins/platforms/whatsapp` e
  `gateway/platforms/whatsapp_common.py`).
- Pelo código tocado:

| Grupo | Commits | Aplicável ao Donkey? |
|---|---:|---|
| só a ponte (`plugins/platforms/whatsapp`, `scripts/whatsapp-bridge`) | 120 | não: outro transporte (Baileys); o Donkey fala a Cloud API |
| Cloud API (`whatsapp_cloud`), com ou sem outros | 37 | lidos commit a commit (abaixo) |
| só `whatsapp_common` | 12 | identidade e allowlist da ponte; ver WA-007 |
| assunto cita WhatsApp, não toca os adapters | 56 | gateway genérico do hermes (aprovações, branding, footguns) |

## Casos

| Caso | Comportamento da API | Commits hermes | Donkey | Status |
|---|---|---|---|---|
| WA-001 | Um app da Meta com vários números entrega a mudança de cada número a todos os webhooks; a de outro número (outro `metadata.phone_number_id`) não é nossa: responder a ela, do nosso número, entra numa conversa alheia. | `4152c69636`, `e5e2d5508f` | `whatsapp_runtime.drainWhatsAppEvents` ignora antes de identificar, sem ack; teste em `t_dm_gate_runtimes` | **portado** |
| WA-002 | A Meta envia webhooks de até 3 MB; um limite menor responde 413 e a Meta descarta o lote depois de tentar de novo. | `e82d71db40` | `http_request_reader.MaxWebhookBodyBytes` = 3 MiB; teste em `t_http_request_reader` | **portado** |
| WA-003 | Envelopes sem conteúdo no campo `messages` (`type` = `system`: troca de número ou de BSUID; `reaction`; `unsupported`/`unknown`) não são mensagens: não iniciam turno. | `f90721e95a` | `whatsapp_pure.parseMessage` só aceita `text`, `interactive` e mídia com id; o resto é `wmkUnknown` e é descartado | coberto |
| WA-004 | Toques em botões (`interactive`) passam pela mesma autorização de DM que o texto. | `f96b2e6ef7` | `drainWhatsAppEvents` autoriza todo evento, `wrkInteractive` incluído | coberto |
| WA-005 | Um segredo de app ausente não pode virar chave de HMAC (o hermes chaveava com a string `"None"`). | `53f84cc716` | o receiver recusa POST sem `whatsappAppSecret` (403) | coberto |
| WA-006 | Comparação de segredo em tempo constante. | `bc7ff51ace` | `safeEquals` no receiver | coberto |
| WA-007 | Entradas de allowlist em formato JID (`@s.whatsapp.net`), com `+` ou pontuação, `*`, e BSUIDs (`BR.abc…`) precisam ser normalizadas para casar com o remetente. | `52c7976f40`, `6c7960cfa0`, `c0d7b05faa`, `a065fe7e3c`, `42e5e8b3d5`, `decdbd15f9`, `810c8777e1`, `f5ca0e2f0b`, `ddfc6342ad`, `b35f219aed` | o Donkey não tem allowlist de números crus: autoriza por usuário interno (pareamento e política de DM) | não se aplica |
| WA-008 | O `context` de uma resposta traz só o `wamid` citado, nunca o texto: para o agente saber a que se responde, é preciso indexar o texto das mensagens recebidas e enviadas por `wamid`. Idem para mídia que o próprio bot enviou. | `619dc4a561`, `c8b56d43da` | nenhum canal do Donkey carrega contexto de resposta ainda | **adiado** (recurso entre canais, não correção do WhatsApp) |
| WA-009 | Desde agosto de 2026 o remetente pode vir como BSUID (`XX.alfanumérico`) em vez do número. | `42e5e8b3d5`, `f90721e95a` | a identidade trata o remetente como opaco, então um BSUID resolve um usuário; **em aberto:** se a Cloud API aceita BSUID como destinatário da resposta (não verificável sem a documentação da Meta) | em aberto |
| WA-010 | Corpo de mensagem interativa com no máximo 1.024 caracteres. | `47f0c6bc0e` | o Donkey não envia mensagens interativas pelo WhatsApp | não se aplica |
| WA-011 | Bind de webhook em IPv4 e IPv6. | `2c771be406` | o receiver liga em `DONKEY_WEBHOOK_HOST`, escolhido pelo operador | não se aplica |

Os demais commits da Cloud API são do gateway do hermes (cartões de
aprovação, armazenamento, perfis multiplex, branding) e não descrevem
comportamento da API.
