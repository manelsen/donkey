# Plano — próximas ~7 h (depois do PR #56)

Regra que vale para tudo abaixo: **não abrir frente nova** enquanto uma das duas
primeiras não estiver em N3. Cada história: TDD com vermelho visível, um dono por
arquivo, auditoria independente antes do merge, suíte completa verde, commit por
história.

## 0. Fechar o PR #56 (15 min)

- suíte completa no tree commitado (280 verdes já observados);
- marcar o PR como ready;
- recalcular o placar da V4 com evidência (as fundações existem, mas os pontos de
  produto ainda não), atualizando `~/git/COBERTURA_HERMES_VS_DONKEY_V4.md`.

## 1. Ferramentas em N3 (≈2 h) — peso 18%

Arquivos: `app/inbound_media.nim`, `app/prompt_building.nim`,
`domain/providers/media_pure.nim`, `app/tools/audio_tools.nim`,
`app/tools/utility_tools.nim`, `app/native_tools.nim`, `app/orchestrator.nim`,
`adapters/channel/telegram.nim`, `src/donkey.nim` (confinamento), testes.

1. **Marcador condicional (H2)**: o texto "a imagem acompanha esta mensagem" só
   pode existir para imagem que realmente foi inline. Hoje o cap de 4 é aplicado
   depois do merge, e um álbum de 10 fotos mente sobre 6.
2. **Cap antes do merge**: limitar quantidade/tamanho antes de decodificar e
   re-serializar; `MaxAttachmentsPerTurn`/`MaxInlineImagesPerTurn` precisam
   limitar o payload de verdade.
3. **Voz com tópico (M3)**: `NativeCtx` carrega `replyTo`; `prepareVoiceReply`
   devolve `replyTo` e o outbox respeita fórum.
4. **`inspect_image` com um só encoder (M6)**: allowlist de MIME + cap, sem
   rotular SVG/BMP como jpeg.
5. **Retry de imagem por turno (M1/M2)**: flag no estado do turno, não na closure;
   cobrir o caminho de streaming (hoje OpenRouter nem tenta).
6. **`isImageRejection` fonte única (M4)**: `file_id`/`attachment` entram na lista
   e saem de `prompt_building`.
7. **Confinamento e higiene**: caminho absoluto só dentro do paddock; TTS grava
   via `attachment_store` (0600, sem symlink); GC de `attachments/`.

Gate: suíte + auditoria de mídia; PR separado.

## 2. Interfaces em N3 (≈2 h) — peso 8%

Arquivos: `app/agent_chat_runtime.nim`, `app/http_gateway.nim`,
`domain/gateway/*`, `app/chat_bridge.nim`, `src/donkey.nim`, `docs/topics`.

1. **US-003 SSE**: chunks `chat.completion.chunk`, `[DONE]`, tool calls em
   streaming, limites de conexão pelo `CapacityPolicy`, erro no meio do stream.
2. **Token por registro no `ChatBridge`**: fecha a janela de 600 s em que um
   terminal atrasado pode ser atribuído ao turno novo.
3. **US-004 dashboard**: sessões, providers e "nova conversa" (mínimo viável,
   read-only + um POST), se o SSE fechar dentro do tempo.
4. **US-005 docs e fechamento**: `docs/topics/interfaces.md`, exemplos `curl`,
   matriz de erros.

Gate: cliente OpenAI real (curl com `stream:true`) + suíte; PR separado.

## 3. Canais LINE ponta a ponta (≈1,5 h) — peso 18%

1. **US-003** ingress compartilhado consumindo `core/security/webhook_auth`;
2. **US-004** adapter LINE (outbound + fila + reply token);
3. **US-005** rota `/webhook/line` + env (`LINE_CHANNEL_SECRET/TOKEN`,
   `LINE_ALLOWED_GROUPS/USERS`) usando `LineSignatureHeader`;
4. **US-006** runtime inbound com `decideLineEvent`/`lineRouting` e
   `LineReplayCache` em um único `var`;
5. **US-007** prova de não-duplicação (um MAC, uma política) e docs.

Gate: simulação de webhook assinado + replay + grupo negado; PR separado.

## 4. Automação e Durabilidade ligadas (≈1,5 h) — 12% somados

1. **Automação US-003+**: scheduler no daemon, persistência de `lastRunAtMs`
   inicializada em `createdAtMs`, `CATCHUP_MAX_H` validado no config (teto 24 h),
   retenção de histórico.
2. **Durabilidade US-003**: recuperação no caminho do turno usando
   `resumeDecision`/`commitIfTerminal`; os dois reinícios que abandonam; aviso
   único ao usuário.

Gate: teste com store real e dois "reinícios"; PR separado.

## 5. Fechamento (30 min)

- recalcular a V4 com os números medidos;
- atualizar `tasks/roadmap-v4.md` com o que virou N3 e o que ficou;
- registrar dívidas: endpoints duplicados (descritor × perfil), `durable_file`,
  `ports/turn_journal`, accessors do supervisor, dedupe de rows do doctor.

## Ordem de paralelização

Ferramentas e Interfaces podem correr em paralelo **só** depois que o PR #56
mergear: elas tocam arquivos disjuntos (`app/tools/*` vs `gateway/*`), com a
exceção de `src/donkey.nim` e `orchestrator.nim`, que ficam com um dono por vez.
Canais e Automação/Durabilidade entram depois, um de cada vez.
