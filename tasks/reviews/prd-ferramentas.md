# Review — `tasks/prd-ferramentas.md`

**Veredito: BLOCK** — 1 história quebra teste existente e 3 critérios são inviáveis como escritos.
O recorte (imagem direta + TTS como voz, V4 §6 p1) está certo; a fiação proposta é que não fecha.

## Bloqueadores
1. **US-002 quebra `tests/app/t_orchestrator.nim`.** `addUserTurnWithImages` capa em 10 hoje
   (`TG-028: the attachment cap keeps the current turn`: 25 urls → `len == 10`), e esse teste não é
   somente-leitura. Sem editar teste: `inlineImagesForTurn` conta/corta **só `data:` URLs** e devolve
   `http(s)`/paths intactos; o cap 4 vale só para o inline.
2. **US-002 muda roteamento e custo sem teste.** `requestApproxChars` soma `msg.imageUrl.len`
   (`core/providers/smart_routing.nim:191`); com `>= LongContextChars (60_000)` a linha 567 escolhe
   outra família de providers e a complexidade sobe (`domain/routing/smart_route.nim:132`). Foto real
   (>45 KB) cai nesse ramo em todo turno. Exigir estimativa fixa por imagem + teste novo.
3. **Reenvio de imagens antigas.** O histórico vivo mantém `imageUrl` (só `trimTo(20)`): com data URLs,
   toda foto volta ao provider nos turnos seguintes. Falta "só o turno atual leva imagem" (sanitizar o
   histórico após responder) + teste de segundo turno sem `data:`.
4. **US-005 sem seam.** `mediaUploadSpec` é `func` pura e não recebe bytes, mas o teste exige
   "corpo contém os bytes do arquivo". Separar `mediaUploadSpec` de
   `mediaUploadBody(spec, data, boundary)` puro; o adapter lê o arquivo.
5. **US-006 não compila como escrito.** `prepareVoiceReply` é `proc` síncrono devolvendo `Result`, mas
   `outbox: AsyncQueue` só tem `put` async (`ask`, `native_tools.nim:1180`). Devolver `OutboundMessage`
   e enfileirar no dispatch, ou `Future[Result[...]] {.async.}`.
6. **US-005 sem teste de adapter** — justamente I/O + multipart. Criar
   `tests/adapters/channel/t_telegram_media_upload.nim` com `HttpRuntimePort` falso (modelo
   `tests/app/t_audio_tools.nim`), provando headers, arquivo, campos e fallback.
7. **Multipart deve preservar o que o JSON faz hoje:** `message_thread_id`/`reply_to_message_id`, retry de
   tópico e `sendPhoto`→`sendDocument` (`telegram.nim:290-305`). Não citado = regressão em fórum/foto grande.
8. **Marcador mentiroso.** `attachmentMarker` é incondicional (`inbound_media.nim:24`); se passar a dizer
   "a imagem acompanha o turno", SVG/oversize mentem e o modelo não chama `inspect_image`. Critério:
   marcador condicional (inline vs. disco) + teste dos dois casos.

## Correções menores (obrigatórias)
- `MaxInlineImageBytes` em bytes crus → ~6,7 MB base64, acima do limite documentado do Anthropic
  (5 MB/imagem): limitar o **codificado** e testar o comprimento do data URL. `withoutInlineImages` em
  álbum: o "último user" pode ser imagem sem texto — nota no último user com texto e descartar turnos
  vazios. `isImageRejection` duplica `genericProviderErrorText` (`prompt_building.nim:196`): uma fonte só.
  `cfSendVoice`: `FullCapability` é compartilhado com Discord; "só ckTelegram" exige const próprio.
  Fallback de upload local não deve vazar caminho absoluto no chat.
- US-004: `rg "base64" adapters/memory → 0` é trivial (não há "base64" lá); usar `rg "msg.imageUrl"` nos
  3 writers. US-007 deve listar `media.md` em `docs/index.md`. **Ownership:** `prd-multiagente` US-004 reivindica `more_tools.nim`, `native_tools.nim`,
  `native_tool_dispatch.nim` e `nativeSessionTools()` em `session_bootstrap.nim`; aqui só se cita provider.
  Redução recomendada: `text_to_speech` com flag `as_voice` (já em `UtilityNativeTools`) em vez de
  `reply_as_voice` + 3 pontos de fiação disputados.
- **Preparação (linha 65) "git status sujo → pare"** bloqueia a missão: o worktree já tem o `prd-provider-transport` em andamento; adotar a regra de lá (parar só se o arquivo for seu).
- US-003 é global (`buildCompleteFn` serve API/subagentes): decidir/documentar o retry sem imagem na API.

## API externa / fixtures
- Telegram: OGG/OPUS e `sendVoice` documentados em `docs/hermes-mining/telegram/CASES.md#tg-029`
  (`hermes-agent/.../standalone.py`: só `.mp3`/`.m4a` em `sendAudio`). O mapa do PRD está correto.
  Falta `duration` (tg-029: sem ele o cliente mostra 0:00) em `MediaUpload`. Sem fixtures: se o teste
  afirmar upload válido, precisa de `.ogg` real; senão, declarar que valida só o framing.

## Ordem sugerida
**US-001** (cap só de `data:` + estimativa fixa) → **US-004** → **US-003** (request sintético) →
**US-002** (depois de fallback/transcript; inclui retenção e routing) → **US-005** (+ teste de adapter) →
**US-006** (preferir `text_to_speech(as_voice)`; coordenar com multiagente) → **US-007**.

## O que está bom
Histórias pequenas, red-first explícito, gates iguais aos do provider PRD, testes existentes somente-leitura;
a análise do hop `inspect_image` (`utility_tools.nim:54`) está factualmente correta.