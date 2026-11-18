# Re-review — `tasks/prd-ferramentas.md`

**Veredito: PASS WITH FIXES.** Os 8 bloqueadores do primeiro review foram resolvidos na arquitetura; restam correções de critério — uma quebra um teste declarado somente-leitura e a duração da voz sai errada.

## Verificado no código

- **TG-028:** `addUserTurnWithImages` mantém o cap 10 (`prompt_building.nim:177-185`) e `tests/app/t_orchestrator.nim:1483-1491` continua 25 `.jpg` → 10. `inlineImagesForTurn` só corta `data:`; `http(s)`/paths intactos. Correto.
- **Roteamento:** `requestApproxChars` soma `imageUrl.len` (`smart_routing.nim:191`) e o corte é `>= LongContextChars` (`:567`); `t_smart_routing.nim:28` só usa URL http, então segue verde. 200 KB inline → 1 024 chars; 61 k texto cruza. Não-objetivo (linha 172) coerente.
- **Histórico:** `demoteInlineImages` em `result.history` após `withLoopResult` (`orchestrator.nim:499`) é antes de `finalizeNormalTurn` (`:502`) e de `saveNumberedSession` (`:617/632`). Correto.
- **Assinaturas:** `mediaUploadSpec`/`mediaUploadBody(spec, data, boundary)` separa os bytes; `prepareVoiceReply` síncrono + `NativeToolResult.outbound` + `await ctx.outbox.put` em `executeNativeCategory` (async, `native_tools.nim:1353`) é compilável e testável por `executeNativeTool`.
- **US-005/ownership/prep:** teste de adapter e fixtures declarados; `audioMethodFor` já mapeia ogg→sendVoice, mp3/m4a→sendAudio (`telegram_policy.nim:139-140`); `as_voice` reusa `UtilityNativeTools`; §4/§5 adotam a exceção de worktree paralelo.

## Correções restantes

1. **Falta `duration` no `sendVoice`.** TG-029 (`CASES.md:377`) diz "sendVoice/sendAudio aceitam `duration`"; o PRD manda só em `sendAudio` (linhas 127/129) e o caminho principal da US-006 é `.opus`→`sendVoice` → 0:00. Incluir em ambos, testar `.opus` e `.m4a`.
2. **`mediaDurationSec` não chega ao spec.** Nenhum critério liga `msg.mediaDurationSec` às chamadas `send`/`sendReturnId` → `sendMedia` (`telegram.nim:370/391`); adicionar parâmetro e repassar `durationSec`, senão o campo é morto.
3. **`t_inbound_media.nim` (somente-leitura) quebra.** O PNG de 3 bytes do teste vira inline, e `:67-68` exige `inspect_image` e `attachments/photo.png` no texto. Fixar o marcador inline com `relPath` + `inspect_image`; isso também evita o marcador mentir no retry da US-003, que remove a imagem.
4. **Retenção sem teste de fiação.** `t_inline_image_retention.nim` chama `demoteInlineImages` à mão; apagar a linha 500 do orchestrator não falha nada. Fazer dois turnos via `runOrchestrator`/`completeFn` falso (2º request sem `data:`).
5. **Enfileiramento sem teste.** `t_voice_reply.nim` só cobre `prepareVoiceReply`; adicionar `executeNativeTool(text_to_speech)` com `AsyncQueue` (modelo `t_native_tools.nim:32`): sucesso → 1 `OutboundMessage`, `ckEmail`/TTS 500 → fila vazia.
6. **Ordem da US-006 contraditória.** A colisão `more_tools`/`native_tools` está declarada, mas `prd-multiagente.md:68-73` manda ferramentas US-003/US-006 antes de multiagente US-006, enquanto a linha 146 manda depois do merge. Alinhar à multiagente; corrigir a linha 58 (US-006 não toca `session_bootstrap.nim`).
7. **Ownership ausente para `domain/message.nim` e `ports/channel_capability.nim`.** `prd-canais.md:90` já serializa `channel_capability` com ferramentas, e o roadmap lista `domain/message.nim` com 4 missões. Declarar ambos (§4.1).
8. **Caminho local inexistente/relativo vaza.** "local e existente" não define o caso ausente; ele cai no fallback de URL e envia o caminho. Definir local como absoluto e neutralizar em leitura falha; testar path inexistente e ausência do caminho no texto.
9. **Upload ignora proxy/allowlist.** `newTelegramAdapter` configura proxy/allowlist/retry (`telegram.nim:672-677`); o default `uploadHttp` proposto não. Derivar do mesmo config para `DONKEY_TELEGRAM_PROXY` valer no upload.
10. **`isImageRejection` encolhe a lista atual.** `genericProviderErrorText` (`prompt_building.nim:195-198`) reconhece `file_id`/`attachment`/`image url`; o PRD cita só `image_url`/`unsupported image`/`invalid content`/`media type`. O teste passa só porque a amostra tem `image_url`; manter a lista completa.

Menores: `MaxInlineImageEncodedBytes` = 5 MiB de data URL é mais restritivo que o limite de 5 MB/imagem do Anthropic (o racional da linha 75 está errado, embora conservador); baseline 242 fixo (linha 189) contra "não hardcode" do `prd-multiagente` §5.3; em `withoutInlineImages`, álbum só-imagem sem turno com texto não define onde vai a nota.
