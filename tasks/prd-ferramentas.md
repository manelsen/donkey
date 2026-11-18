[PRD]
# PRD: Ferramentas — imagem direta no turno e resposta em voz

> **Executor:** agente autônomo. Leia este documento inteiro antes de começar. Execute as histórias **na ordem**, um commit por história, com os quality gates verdes. Não abra a história seguinte com a anterior vermelha.

## 1. Contexto

A V4 (`COBERTURA_HERMES_VS_DONKEY_V4.md`, §6, prioridade 1) mede Ferramentas em **60%** contra 95% do Hermes. O recorte aprovado é comportamento, não breadth: imagem direta no turno e TTS entregue como voz.

Hoje a imagem do canal nunca chega ao modelo no turno. `src/donkey.nim:1313` chama `processInboundMediaDownload`; `applyInboundAttachment` (`src/donkey/app/inbound_media.nim`) grava em `attachments/`, escreve o marcador `[Imagem anexada: … Use inspect_image]` e **zera `msg.mediaUrl`** (linha 62). Sem `mediaUrl`, `encodeSessionPayload` (`app/session_bootstrap.nim:352`) entrega só texto, e o modelo gasta um round-trip em `inspect_image` (`app/tools/utility_tools.nim:54`), que relê o arquivo, re-encoda e chama o provider de novo. Os envelopes de imagem já existem e estão testados (`domain/providers/media_pure.nim`); falta a origem — e falta não quebrar o que já depende do marcador e do histórico.

O TTS tem o problema espelhado: `text_to_speech` grava `attachments/tts-*` e devolve o caminho (`app/tools/audio_tools.nim:111`), mas o Telegram só envia mídia por URL — `sendMedia` põe o valor cru em `photo`/`voice`/`audio` (`adapters/channel/telegram.nim:264`) e o adapter só faz POST JSON (`postWith`, linha 110). `audioMethodFor` (`domain/channels/telegram_policy.nim:122`) já escolhe `sendVoice`/`sendAudio` pelo sufixo, mas nunca recebe arquivo local.

| Lacuna | Consequência | Correção |
|---|---|---|
| Imagem inbound vira só marcador | 2 chamadas ao provider por imagem | inline no 1º turno + retenção |
| Áudio local não é enviável | TTS existe, voz não | multipart + `duration` |

## 2. Objetivos

1. Imagem inbound suportada vira parte `imageUrl` do **primeiro** turno, sem `inspect_image` obrigatório, com marcador condicional que não mente.
2. O inline não muda custo/roteamento (estimativa fixa) e não volta nos turnos seguintes nem no transcript.
3. Arquivo, mime ou provider que recusam degradam para texto; marcador + `inspect_image` seguem como caminho.
4. `text_to_speech` pode entregar a resposta como voz no Telegram, com fallback de texto em qualquer falha.
5. Zero `raise` novo fora de adapter; puro em `domain/`; I/O devolve `Result`.

## 3. Fora de escopo

- Computer use de desktop, X11, screenshot; voice mode, wake word, áudio contínuo, barge-in.
- STT de voz inbound como turno (o `transcribe_audio` atual fica como está).
- Voz em canais além do Telegram; os demais seguem só texto.
- Conversão de áudio (`ffmpeg`), normalização, streaming de voz, vídeo, OCR, descrição automática de imagem sem pedido.
- Reescrever envelopes de imagem dos providers (a V4 já os entregou).
- Copiar código do hermes-agent. Transfere-se o comportamento, não a implementação.

## 4. Quality gates

Obrigatórios ao fim de **toda** história:

```bash
bash scripts/check_boundaries.sh
nimble build -y
JOBS=6 bash scripts/run_tests.sh
git diff --check
```

Regras, sem exceção:

- TDD: escreva o teste, **mostre o vermelho** (`run_tests.sh <arquivo>` com o erro esperado), implemente o mínimo, mostre o verde, rode os gates, commite com o vermelho → verde no corpo do commit.
- Lógica pura em `domain/`/`core/` como `func`; adapter só faz ligação. Proibido `raise` fora de adapter; I/O falível devolve `Result[T, string]`.
- Nenhum teste novo usa rede, provider real, Docker ou Telegram real; HTTP é falso (modelo: `tests/app/t_audio_tools.nim`).
- Nenhum teste existente é editado para “acomodar” a mudança; se precisar mudar, o comportamento mudou e a história diz isso.
- Worktree sujo: **só pare se a alteração estiver num arquivo que esta missão vai tocar** (o `prd-provider-transport` já está em andamento). Registre o que encontrou; nunca use stash, reset ou checkout sobre trabalho alheio.

### 4.1 Paralelização e donos de arquivo

- Cada história é dona do seu arquivo de teste; histórias diferentes podem ser redigidas em paralelo.
- `src/donkey/app/session_bootstrap.nim` tem **um escritor por vez**: disputado com `tasks/prd-provider-transport.md` (US-001) e com a US-003 daqui (a US-006 **não** toca esse arquivo).
- **Donos nesta missão:** `domain/message.nim` e `ports/channel_capability.nim` são da US-005. `ports/channel_capability.nim` **não roda em paralelo** com `tasks/prd-canais.md` (US-000, `cfSendVoice`); `domain/message.nim` está no roadmap compartilhado e ninguém mais o edita durante a US-005.
- **Colisão declarada:** `tasks/prd-multiagente.md` §4.1 fixa a ordem provider US-001 → ferramentas US-003/US-006 → multiagente US-006. A US-006 daqui roda **antes** das histórias de tool daquele PRD, toca só `more_tools.nim` (bloco `text_to_speech`) e `native_tools.nim` (branch + enfileiramento) e **não** toca `native_tool_dispatch.nim` nem `nativeSessionTools()`. A precedência vai no commit.
- Somente leitura: `tests/app/t_orchestrator.nim` (TG-028), `tests/app/t_inbound_media.nim`, `tests/app/t_prompt_building.nim`, `tests/domain/providers/t_media_pure.nim`, `tests/core/t_smart_routing.nim`, `tests/domain/channels/t_telegram_policy.nim`, `tests/ports/t_channel_capability.nim`, `tests/channel/t_telegram.nim`.
- `run_tests.sh` completo e commits são sequenciais na sessão principal.

## 5. Preparação (antes da US-001)

1. `cd ~/git/donkey && git status --short`; anote os arquivos sujos e aplique a regra da §4 (parar só se for arquivo seu).
2. `git fetch origin && git switch master && git pull --ff-only`. 3. Criar a branch `feat/ferramentas-midia`. 4. Registrar no commit de abertura que este PRD é a fonte de verdade.

## 6. Histórias

### US-001: Decisão pura de inline e de custo

**Descrição:** Como mantenedor, quero que aceitar/recusar inline e quanto ele “custa” no roteamento sejam funções puras e testadas.

**Critérios de aceite:**
- [ ] `domain/providers/media_pure.nim` ganha `MaxInlineImageEncodedBytes* = 5 * 1024 * 1024` (limite medido no **comprimento do data URL**; ≈3,7 MB crus, conservador frente aos 5 MB/imagem do Anthropic e aos 20 MB da OpenAI), `MaxInlineImagesPerTurn* = 4`, `func imageDataUrl*(mime: string; data: openArray[byte]): Result[string, string]` (só `SupportedImageMimes`, recusa vazio e resultado acima do limite) e `func inlineImagesForTurn*(urls: seq[string]): seq[string]` que conta/corta **apenas entradas `data:`**; `http(s)`/caminhos passam intactos e na ordem.
- [ ] `core/providers/smart_routing.nim` ganha `InlineImageApproxChars* = 1_024` e `func approxCharsForImage*(url: string): int` (`data:` → constante; resto → `url.len`); `requestApproxChars` (linha 187) usa a função. `hasImage` continua verdadeiro para inline.
- [ ] `tests/domain/providers/t_inline_image_pure.nim`: prefixo `data:image/png;base64,`; `image/svg+xml` recusado; data URL exatamente no limite aceito e limite+1 recusado; 6 `data:` viram 4 na ordem; 25 `.jpg` saem intactos.
- [ ] `tests/core/t_routing_inline_image.nim`: request com data URL de 200 KB **não** cruza `LongContextChars` (60 000); request com 61 000 chars de texto continua cruzando; `tests/core/t_smart_routing.nim` e `t_media_pure.nim` passam sem edição.

**Notas:** smart routing **é tocado**, mas só na estimativa de caracteres; seleção, famílias e thresholds não mudam.

### US-002: Transcript sem base64 de imagem

**Descrição:** Como operador, quero que uma foto não infle o `.jsonl` da sessão.

**Critérios de aceite:**
- [ ] `domain/memory/transcript_pure.nim` ganha `const InlineImageRef* = "inline"` e `func transcriptImageRef*(imageUrl: string): string`: `data:` → `InlineImageRef`, resto inalterado.
- [ ] `adapters/memory/md_file.nim:848`, `markdown.nim:202` e `sqlite_store.nim:205` gravam `transcriptImageRef(msg.imageUrl)`; `rg -n '"imageUrl": msg.imageUrl' src/donkey/adapters/memory` → 0 e `rg -n "transcriptImageRef" src/donkey/adapters/memory` → 3.
- [ ] `tests/memory/t_transcript_image_ref.nim` prova a função e um `saveSession` real via `MdFileAdapter` com imagem `data:` cujo arquivo **não** contém `base64` nem `data:image`.
- [ ] Testes existentes de memória passam sem edição.

**Notas:** a US-004 já remove o inline do histórico; este writer é a garantia final (import de sessão, restore, outros backends).

### US-003: Degradação quando o provider recusa a imagem

**Descrição:** Como usuário, quero texto quando o modelo não tem visão, não erro.

**Critérios de aceite:**
- [ ] `media_pure.nim` ganha `func isImageRejection*(error: string): bool` como **fonte única** da lista **completa** de hoje (`image_url`, `image url`, `file_id`, `attachment`, `invalid content`, `unsupported image`, `media type`); `genericProviderErrorText` (`app/prompt_building.nim:195-198`) passa a chamá-la — `rg -n "image_url|attachment|unsupported image" src/donkey/app/prompt_building.nim` → 0 e o texto exibido ao usuário não muda.
- [ ] `func withoutInlineImages*(req: CompletionRequest): CompletionRequest`: remove só `imageUrl` iniciado em `data:`, preserva `http(s)`, anexa a nota `[imagem removida: provider sem visão]` ao **último turno de usuário com texto** e descarta turnos que ficarem sem texto e sem imagem. Se não existir turno com texto (álbum só de imagens), a nota vai para o último turno de usuário, que é **mantido** em vez de descartado.
- [ ] `buildCompleteFn` e `buildAsyncCompleteFn` (`app/session_bootstrap.nim`) repetem o loop **uma vez** com `withoutInlineImages` quando todas as seleções falharam por `isImageRejection` e havia imagem inline.
- [ ] `tests/app/t_image_fallback.nim` com builder falso: 2 chamadas, a segunda com `imageUrl == ""` e a nota no turno com texto; álbum só de imagens não deixa turno vazio; erro de outra natureza e request sem inline → 1 chamada (contador).
- [ ] `tests/app/t_prompt_building.nim`, `t_provider_credentials.nim` e `t_provider_executor.nim` passam sem edição; nenhuma chamada de rede.

**Notas:** o retry é global (`buildCompleteFn` serve canal, API e subagentes). Isso é aceito e documentado na US-007 + no commit; o teste cobre a função, não a API.

### US-004: Imagem inbound no primeiro turno, sem reenvio

**Descrição:** Como usuário, quero que a foto que enviei já esteja no turno — e não em todos os turnos seguintes.

**Critérios de aceite:**
- [ ] `applyInboundAttachment` (`app/inbound_media.nim`) usa US-001: imagem suportada dentro do limite → `msg.mediaUrl = dataUrl`; o resto segue `mediaUrl = ""`.
- [ ] `attachmentMarker` ganha `inline: bool`. O texto **não-inline é byte a byte o de hoje**; o inline mantém `relPath`, mime, tamanho e a instrução `Use inspect_image com path="<relPath>"`, acrescentando que a imagem já acompanha a mensagem. Assim `tests/app/t_inbound_media.nim` (**somente leitura**) continua verde sem edição: o PNG de 3 bytes vira inline e as asserções `inspect_image`, `attachments/photo.png` e `file_id notin` seguem válidas. Os dois casos são testados.
- [ ] `addUserTurnWithImages` (`app/prompt_building.nim:165`) usa `inlineImagesForTurn` **mantendo** o cap `MaxAttachmentsPerTurn = 10` existente; `tests/app/t_orchestrator.nim` (TG-028, 25 urls → 10) fica **somente leitura** e verde.
- [ ] Retenção: `media_pure.nim` ganha `func demoteInlineImages*(h: ConversationHistory): ConversationHistory` (zera só `imageUrl` iniciado em `data:`); `app/orchestrator.nim` aplica em `result.history` logo após `withLoopResult` (linha ~499), antes de `finalizeNormalTurn` e de `saveNumberedSession`. O turno atual já foi enviado; o próximo não reenvia.
- [ ] `tests/app/t_inline_image_turn.nim`: png de 3 bytes → `mediaUrl` decodifica de volta e o texto não contém `file_id`; `image/svg+xml` e oversize → `mediaUrl == ""` com marcador para disco; 6 data URLs → 4 mensagens com `imageUrl`.
- [ ] `tests/app/t_inline_image_retention.nim` **fia o orchestrator**: dois turnos no mesmo `runOrchestrator` (modelo `tests/app/t_orchestrator.nim:331`) com `completeFn` que grava as requests; a 1ª leva `data:`, a 2ª não, e o marcador de texto sobrevive. Apagar a linha do `orchestrator.nim` derruba o teste — chamar `demoteInlineImages` à mão não conta.

### US-005: Telegram envia mídia local por multipart

**Descrição:** Como usuário, quero receber o áudio que só existe como arquivo, com o mesmo comportamento de tópico/foto que o JSON tem hoje.

**Critérios de aceite:**
- [ ] `ports/channel_capability.nim`: flag `cfSendVoice` + campo `sendVoice`; const próprio `TelegramCapability = FullCapability + sendVoice` (não mutar `FullCapability`, compartilhado com Discord); no registry só `ckTelegram` é `true`.
- [ ] `TelegramAdapter` ganha `uploadHttp*: HttpRuntimePort` + parâmetro opcional no construtor (padrão do QQ Official), com **a mesma configuração do `http` de texto** (`telegram.nim:672-677`): `telegramProxyUrl()`, allowlist (`api.telegram.org` só quando `apiBase` é vazio), `retryNonIdempotent = false`, `retryConflict = true` e `telegramMediaTimeoutSec()` — nenhum desvio.
- [ ] `domain/channels/telegram_policy.nim`: `MediaUpload` (`method`, `field`, `mime`, `chatId`, `caption`, `threadId`, `replyTo`, `durationSec`) + `func mediaUploadSpec*(path: string; chatId: int64; caption: string; threadId = ""; replyTo = ""; durationSec = 0): MediaUpload` (método via `audioMethodFor`; `.mp3`/`.m4a` seguem `sendAudio`) + `func mediaUploadBody*(spec: MediaUpload; data: string; boundary: string): string`.
- [ ] `domain/message.nim`: `OutboundMessage.mediaDurationSec*: int = 0`; `send`/`sendReturnId` (`telegram.nim:368/389`) repassam para `sendMedia(..., durationSec = msg.mediaDurationSec)`. `sendVoice` **e** `sendAudio` incluem `duration` quando `durationSec > 0` (TG-029 vale para os dois: sem ele o cliente mostra 0:00) e omitem quando 0.
- [ ] `sendMedia*(a; tgId: int64; url, caption, replyTo: string; durationSec = 0)` (`telegram.nim:264`): só é local o caminho **absoluto** que existe → lê os bytes e faz POST multipart em `uploadHttp`, preservando `message_thread_id`/`reply_to_message_id`, o retry de tópico (`isMissingThreadError`) e `sendPhoto` → `sendDocument`. `http(s)` mantém o caminho JSON de hoje, inclusive o fallback de URL em texto. Caminho relativo, inexistente ou leitura falha → const `TelegramMediaFallbackText*` em `telegram_policy.nim` ("Não foi possível enviar o anexo."), **sem caminho e sem nome de arquivo**.
- [ ] `tests/domain/channels/t_telegram_upload_pure.nim`: `.ogg` → `sendVoice`/`voice`/`audio/ogg`; `.m4a`/`.mp3` → `sendAudio`/`audio/*`; `.png` → `sendPhoto`; `.pdf` → `sendDocument`; corpo com `chat_id`, `caption`, `message_thread_id`, `reply_to_message_id`, `filename` e os bytes; `duration` presente em `sendVoice` **e** em `sendAudio` quando `durationSec > 0`, ausente quando 0.
- [ ] `tests/adapters/channel/t_telegram_media_upload.nim` com `HttpRuntimePort` falso: URL traz o método, header multipart, bytes do fixture e `duration` em `sendVoice` e `sendAudio`; foto falha → segundo POST `sendDocument`; erro de tópico → retry sem `message_thread_id`; inexistente e falha total → texto exatamente `TelegramMediaFallbackText`, sem `/`, sem `attachments` e sem `sample.*`.
- [ ] Fixtures `tests/fixtures/media/sample.ogg` e `sample.m4a` (≈1 s, < 20 KB) commitados; se não houver como gerar áudio no ambiente, declare no teste que se valida framing + mime, não o áudio decodificado.
- [ ] `tests/domain/channels/t_telegram_policy.nim`, `tests/ports/t_channel_capability.nim` e `tests/channel/t_telegram.nim` passam sem edição.

### US-006: `text_to_speech` entrega voz (sem tool nova)

**Descrição:** Como usuário, quero pedir “me responde em áudio” e receber nota de voz — sem uma segunda tool concorrente com a de TTS.

**Critérios de aceite:**
- [ ] `domain/more_tools.nim` (só o bloco `text_to_speech`): schema ganha `as_voice` (bool, default `false`) e `caption`; a descrição explica que `as_voice` entrega a fala no canal quando houver suporte. Nenhum `*ToolName` novo.
- [ ] `domain/media/audio_pure.nim` ganha `func estimateSpeechSeconds*(text: string): int` (≈2,5 palavras/s, mínimo 1) para a duração de voz/áudio (`sendVoice` e `sendAudio`).
- [ ] `app/tools/audio_tools.nim` ganha `proc prepareVoiceReply*(text, caption, paddockDir: string; channel: ChannelKind; uid: UserId; http: HttpRuntimePort): Result[OutboundMessage, string]`: checa `supports(channel, cfSendVoice)` **antes** do TTS, sintetiza com `performSpeech(format = "opus")` e devolve a mensagem (`mediaUrl` absoluto, `text = caption`, `mediaDurationSec = estimateSpeechSeconds(text)`) **sem** enfileirar.
- [ ] `app/native_tools.nim` (só `TextToSpeechToolName` + o enfileiramento): `NativeToolResult` ganha `outbound*: Option[OutboundMessage]`; a branch preenche com `prepareVoiceReply` e `executeNativeCategory` (async) faz `await ctx.outbox.put`. **Não toca** `native_tool_dispatch.nim` nem `nativeSessionTools()`.
- [ ] Fallback: canal sem `cfSendVoice`, TTS com erro ou áudio vazio → `err` legível, outbox intocada e resposta final em texto; nenhum arquivo `tts-*` órfão quando o TTS falha.
- [ ] `tests/app/t_voice_reply.nim`: (a) com HTTP falso, `prepareVoiceReply` no Telegram + 200 → `attachments/tts-*.opus` existe, `mediaUrl` absoluto, caption e `mediaDurationSec > 0`; `ckEmail` → erro, **zero** POST de TTS; TTS 500 → erro e nenhum arquivo. (b) **fiação**: `executeNativeTool("text_to_speech", as_voice = true)` com `NativeCtx` + `AsyncQueue` (modelo `tests/app/t_native_tools.nim:32`) → exatamente 1 `OutboundMessage` na fila; `ckEmail` e TTS 500 → fila vazia.
- [ ] `tests/app/t_audio_tools.nim` e `t_native_tools.nim` passam sem edição.

**Notas de coordenação:** `more_tools.nim` e `native_tools.nim` são compartilhados com `prd-multiagente`; pela §4.1 daquele PRD esta história roda **antes** das histórias de tool dele, e a precedência fica registrada no commit. Toque só nos blocos citados.

### US-007: Documentar e fechar a missão

**Descrição:** Como mantenedor, quero os dois fluxos, os limites e o custo documentados.

**Critérios de aceite:**
- [ ] Criar `docs/topics/media.md` (e listar em `docs/index.md`): fluxo de imagem (canal → attachments → data URL → parte inline → retenção/degradação → `inspect_image`), fluxo de voz (texto → TTS → multipart → `sendVoice`/`sendAudio` → fallback texto), tabela de limites (`MaxInlineImageEncodedBytes`, `MaxInlineImagesPerTurn`, `InlineImageApproxChars`, `cfSendVoice`) e a nota de que o retry sem imagem vale também para API/subagentes.
- [ ] `rg -n "inspect_image" src/donkey/app/inbound_media.nim` confirma o fallback; `rg -n "media.md" docs/index.md` confirma o índice.
- [ ] Registrar no commit que o placar da V4 não é reescrito por esta missão.

## 7. Requisitos funcionais

- **FR-1:** Imagem inbound suportada entra no primeiro turno como `imageUrl` data URL; o marcador é sempre escrito e é **condicional** ao inline.
- **FR-2:** Mime fora de `SupportedImageMimes` ou data URL acima de `MaxInlineImageEncodedBytes` nunca é inline; o caminho fica no texto.
- **FR-3:** No máximo `MaxInlineImagesPerTurn` entradas `data:` por turno; `http(s)`/caminhos preservam o cap atual de 10 anexos.
- **FR-4:** `requestApproxChars` conta inline por `InlineImageApproxChars`; roteamento e famílias não mudam além disso.
- **FR-5:** Depois do turno, nenhum `data:` permanece no histórico vivo nem no transcript.
- **FR-6:** Rejeição de imagem pelo provider dispara **um** retry sem inline e uma nota no turno com texto.
- **FR-7:** O Telegram envia arquivo local absoluto por multipart, com método por sufixo, `duration` em `sendVoice` **e** `sendAudio`, tópico/reply preservados e fallback neutro sem caminho nem nome de arquivo.
- **FR-8:** `text_to_speech(as_voice)` só entrega voz em canal com `cfSendVoice`; em qualquer falha, nada é enfileirado e o texto responde.
- **FR-9:** Nenhum `raise` novo fora de adapter; toda borda devolve `Result`.

## 8. Não-objetivos

- Tornar `inspect_image` obsoleto (segue para recorte/zoom) ou enviar mídia gerada/baixada no turno.
- Mudar seleção, famílias ou thresholds de roteamento; `ProviderCaps`, cooldown ou catálogo de modelos.
- Auto-detecção de “modo voz” por preferência; STT de áudio inbound como turno.
- Voz em Discord/WhatsApp/Signal nesta missão; `cfSendVoice` para Discord fica para depois.

## 9. Considerações técnicas

- `media_pure.nim`, `transcript_pure.nim`, `audio_pure.nim` e `telegram_policy.nim` são puros: nada de `os`, `http` ou leitura de arquivo; base64 via `std/base64`.
- `applyInboundAttachment` já recebe os bytes do download: montar o data URL não adiciona leitura de disco.
- O adapter do Telegram é a única camada que lê o arquivo local e fala HTTP; a montagem do multipart fica em `domain`.
- `NativeCtx` já expõe `paddockDir`, `http`, `outbox`, `channel` e `uid`; a voz reusa esses campos.
- Se um teste existente precisar mudar em qualquer história, pare: a missão é aditiva.

## 10. Métricas de sucesso

- Foto inbound consome **1** chamada ao provider e **0** `inspect_image`; o 2º turno e o `.jsonl` não contêm `data:` (`t_inline_image_turn.nim`, `t_inline_image_retention.nim`, `t_transcript_image_ref.nim`).
- data URL de 200 KB não muda a faixa de contexto (`t_routing_inline_image.nim`).
- Pedido de voz no Telegram = TTS + `sendVoice`/`sendAudio` com `duration`; falha ainda entrega texto (`t_voice_reply.nim`, `t_telegram_media_upload.nim`).
- Suíte total verde, com o total do run registrado no commit (referência V4: 242 passed) e **zero** testes existentes editados; `check_boundaries.sh` continua 0.

## 11. Questões em aberto

- `MaxInlineImageEncodedBytes` = 5 MiB de data URL (≈3,7 MB crus) é conservador: fica abaixo dos 5 MB/imagem do Anthropic e dos 20 MB da OpenAI. Calibrar com fotos reais antes de congelar, junto com as 4 imagens/turno.
- Legenda da voz: reutilizar o texto falado (cortado em 1024) ou `caption` curta? O schema já prevê `caption`.
- `estimateSpeechSeconds` é aproximação por palavras; se o cliente reclamar de 0:01/0:03, avaliar ler a duração do container numa missão futura.
- Vale um modo automático (`voice_replies = "on"` em PREFERENCES.md) além de `as_voice`? Decidir depois de medir uso.
- O retry sem imagem também deve valer para a API externa? Hoje vale por construção; confirmar com uso.
[/PRD]
