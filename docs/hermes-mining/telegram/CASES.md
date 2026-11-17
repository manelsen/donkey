# Casos — comportamento da Bot API extraído do histórico do hermes

Cada caso agrupa commits do hermes que descrevem o mesmo comportamento da
API. A implementação no Donkey é escrita a partir desta descrição, não do
código do hermes. Ver `THIRD_PARTY_NOTICES.md` para a atribuição MIT.

### TG-001: O limite de 4096 é contado em unidades UTF-16
- **Categoria:** FORMAT
- **Comportamento da API:** O campo `text` do sendMessage aceita no máximo 4096 unidades UTF-16. Caracteres fora do BMP (emoji) ocupam duas unidades e quatro bytes UTF-8.
- **Gatilho / entrada:** Resposta longa, com emoji ou texto CJK, acima do limite.
- **Comportamento esperado do cliente:** Dividir em partes de no máximo 4096 unidades UTF-16, sempre em fronteira de caractere; nunca cortar uma sequência UTF-8.
- **Fontes no hermes:** `9e992df8ae`, `b7c4369ca0`, `c0da5d09a6`, `022d196f38`
- **Testes no hermes:** `tests/gateway/test_discord_reply_mode.py;tests/gateway/test_platform_base.py`
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/domain/channels/telegram_split.nim:14` e `tests/domain/channels/t_telegram_split.nim`
- **Prioridade:** P0

### TG-002: "message is not modified" não é falha de edição
- **Categoria:** EDIT
- **Comportamento da API:** editMessageText devolve erro 400 com descrição "message is not modified" quando o texto enviado é idêntico ao atual. A mensagem está correta.
- **Gatilho / entrada:** Editar uma mensagem com o mesmo conteúdo (streaming, retry, re-render).
- **Comportamento esperado do cliente:** Tratar esse erro como sucesso e não reenviar a mensagem como nova.
- **Fontes no hermes:** `7ac9088d5c`, `6483c39f84`
- **Testes no hermes:** `tests/gateway/test_native_admission_edit.py`
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/domain/channels/telegram_policy.nim:8` e `src/donkey/adapters/channel/telegram.nim:252`
- **Prioridade:** P0

### TG-003: Updates de bots não são entrada de usuário
- **Categoria:** INBOUND
- **Comportamento da API:** getUpdates entrega mensagens de outros bots em grupos (quando o bot tem privacidade desativada) e pode reentregar as próprias mensagens.
- **Gatilho / entrada:** Outro bot escreve no grupo; o bot recebe o update.
- **Comportamento esperado do cliente:** Descartar updates cujo `from.is_bot` é verdadeiro, incluindo o próprio bot.
- **Fontes no hermes:** `fbfe294882`, `6fb25f86ac`, `3a37785f7f`
- **Testes no hermes:** `tests/gateway/test_telegram_group_gating.py;tests/gateway/test_bot_loop_guard.py`
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/domain/channels/telegram_pure.nim:95` e `tests/domain/channels/t_telegram_pure.nim`
- **Prioridade:** P0

### TG-004: Mensagem sem `from` não pode derrubar o parsing
- **Categoria:** INBOUND
- **Comportamento da API:** Mensagens de admin anônimo em grupos e posts de canal chegam sem o objeto `from`; o campo é opcional no update.
- **Gatilho / entrada:** Admin anônimo escreve no grupo, ou um post de canal chega em um chat de discussão.
- **Comportamento esperado do cliente:** Tratar `from` ausente sem exceção: usar o chat como identidade e seguir.
- **Fontes no hermes:** `1a9a2d7fe8`, `c419cf7c86`, `704872a62f`
- **Testes no hermes:** `tests/gateway/test_telegram_group_gating.py;tests/gateway/test_telegram_channel_posts.py`
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/domain/channels/telegram_pure.nim:48` e `tests/domain/channels/t_telegram_pure.nim`
- **Prioridade:** P0

### TG-005: Âncora de resposta inexistente é descartada, não falha o envio
- **Categoria:** INBOUND
- **Comportamento da API:** sendMessage com `reply_to_message_id` de uma mensagem apagada devolve 400 "message to be replied not found".
- **Gatilho / entrada:** Responder a uma mensagem que foi apagada entre o recebimento e o envio.
- **Comportamento esperado do cliente:** Reenviar sem a âncora em vez de perder a resposta.
- **Fontes no hermes:** `b60cfd6ce6`, `713e2274cf`, `29cda7a5ef`
- **Testes no hermes:** `tests/gateway/test_telegram_thread_fallback.py;tests/gateway/test_telegram_reply_mode.py`
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/domain/channels/telegram_policy.nim:20` e `src/donkey/adapters/channel/telegram.nim:113`
- **Prioridade:** P0

### TG-006: Texto vazio ou só espaços é recusado pela API
- **Categoria:** FORMAT
- **Comportamento da API:** sendMessage com `text` vazio ou apenas espaços devolve 400 "message text is empty".
- **Gatilho / entrada:** Resposta do modelo vazia, ou formatação que resulta em string vazia.
- **Comportamento esperado do cliente:** Não chamar a API para texto vazio; enviar um marcador ou pular o envio.
- **Fontes no hermes:** `83dec2b3ec`
- **Testes no hermes:** -
- **Situação no Donkey:** AUSENTE
- **Evidência no Donkey:** `rg -n "strip.len == 0|text is empty" src/donkey/adapters/channel/telegram.nim` (sem guarda); envio em `src/donkey/adapters/channel/telegram.nim:193`
- **Prioridade:** P1

### TG-007: Legenda de mídia tem limite próprio de 1024 caracteres
- **Categoria:** MEDIA
- **Comportamento da API:** O `caption` de sendPhoto/sendDocument/sendVideo aceita no máximo 1024 caracteres, menor que o limite de 4096 do corpo.
- **Gatilho / entrada:** Enviar mídia com legenda longa.
- **Comportamento esperado do cliente:** Truncar ou dividir a legenda antes do envio, preservando o texto completo em mensagem separada.
- **Fontes no hermes:** `f828b087e7`, `fdf1f10fe2`
- **Testes no hermes:** `tests/gateway/test_telegram_voice_caption_markdown.py`
- **Situação no Donkey:** AUSENTE
- **Evidência no Donkey:** `rg -n "1024" src/donkey/adapters/channel/telegram.nim` (sem resultados); legenda crua em `src/donkey/adapters/channel/telegram.nim:142`
- **Prioridade:** P1

### TG-008: Edição também respeita o limite de 4096
- **Categoria:** EDIT
- **Comportamento da API:** editMessageText tem o mesmo limite de 4096 unidades UTF-16 do sendMessage; acima disso a API recusa a edição.
- **Gatilho / entrada:** Streaming de uma resposta longa que cresce além do limite.
- **Comportamento esperado do cliente:** Dividir a edição ou finalizar a mensagem atual e continuar em outra.
- **Fontes no hermes:** `bf1f40996f`, `d7607292d9`
- **Testes no hermes:** -
- **Situação no Donkey:** AUSENTE
- **Evidência no Donkey:** `rg -n "splitForTelegram|splitChunks" src/donkey/adapters/channel/telegram.nim` → só o caminho de envio; edição em `src/donkey/adapters/channel/telegram.nim:242`
- **Prioridade:** P1

### TG-009: callback_data é limitado a 64 bytes
- **Categoria:** FORMAT
- **Comportamento da API:** O `callback_data` de um botão inline aceita no máximo 64 bytes; acima disso o sendMessage é recusado.
- **Gatilho / entrada:** Botão com identificador longo (modelo, skill, sessão).
- **Comportamento esperado do cliente:** Usar um token curto e resolver o valor completo no servidor.
- **Fontes no hermes:** `6fb57bc9cf`
- **Testes no hermes:** `tests/gateway/test_telegram_clarify_buttons.py`
- **Situação no Donkey:** PARCIAL
- **Evidência no Donkey:** `src/donkey/adapters/channel/common_runtime.nim:70` (tokens curtos só para modelos); demais botões em `src/donkey/adapters/channel/telegram.nim:173`
- **Prioridade:** P1

### TG-010: A ação de digitação expira em cerca de 5 segundos
- **Categoria:** RATE
- **Comportamento da API:** sendChatAction('typing') tem efeito por aproximadamente 5 s; depois o indicador desaparece sem aviso.
- **Gatilho / entrada:** Turno longo com ferramentas.
- **Comportamento esperado do cliente:** Reenviar a ação periodicamente enquanto o turno estiver ativo, sem exceder o flood control.
- **Fontes no hermes:** `5948ab52e2`, `1856bd9cc8`
- **Testes no hermes:** `tests/gateway/test_telegram_typing_backoff.py`
- **Situação no Donkey:** PARCIAL
- **Evidência no Donkey:** `src/donkey/adapters/channel/telegram.nim:130` (envio único, sem re-arme)
- **Prioridade:** P2

### TG-011: 429 traz retry_after e deve ser respeitado
- **Categoria:** RATE
- **Comportamento da API:** Ao exceder o limite de envio, a API responde 429 com `parameters.retry_after` em segundos.
- **Gatilho / entrada:** Rajada de mensagens ou edições no mesmo chat.
- **Comportamento esperado do cliente:** Aguardar o retry_after informado antes de tentar de novo.
- **Fontes no hermes:** `404b06ac4f`, `75d92e3d7b`
- **Testes no hermes:** `tests/gateway/test_send_retry.py`
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/adapters/http/std_http.nim:54` (lê `parameters.retry_after`)
- **Prioridade:** P2

### TG-012: O flood control é por chat, não global
- **Categoria:** RATE
- **Comportamento da API:** O limite de envio é aplicado por chat; uma penalidade em um chat não bloqueia os demais.
- **Gatilho / entrada:** Vários chats ativos ao mesmo tempo.
- **Comportamento esperado do cliente:** Manter a janela de penalidade por chat e não serializar todos os envios.
- **Fontes no hermes:** `fb2f3e213a`, `595f3a289c`
- **Testes no hermes:** -
- **Situação no Donkey:** PARCIAL
- **Evidência no Donkey:** `src/donkey/adapters/http/std_http.nim:54` (retry por requisição, sem janela por chat)
- **Prioridade:** P1

### TG-013: Resposta dividida retoma da parte recusada
- **Categoria:** RATE
- **Comportamento da API:** Se uma parte de uma resposta dividida for recusada por flood control, as partes já enviadas não devem ser repetidas.
- **Gatilho / entrada:** Envio de mensagem longa em partes durante uma penalidade.
- **Comportamento esperado do cliente:** Retomar apenas da parte que falhou, mantendo a ordem por chat.
- **Fontes no hermes:** `595f3a289c`, `7efba7c85f`
- **Testes no hermes:** -
- **Situação no Donkey:** AUSENTE
- **Evidência no Donkey:** `rg -n "resume|refused chunk" src/donkey/adapters/channel/telegram.nim` (sem resultados); loop em `src/donkey/adapters/channel/telegram.nim:209`
- **Prioridade:** P1

### TG-014: Mensagem dividida pelo cliente continua um único turno
- **Categoria:** INBOUND
- **Comportamento da API:** O cliente do Telegram divide textos longos em várias mensagens, que chegam como updates separados e em sequência.
- **Gatilho / entrada:** Usuário cola um texto maior que o limite de composição.
- **Comportamento esperado do cliente:** Agrupar os fragmentos que chegam em sequência em um único turno.
- **Fontes no hermes:** `d156942419`, `5075717949`, `ed74264afe`
- **Testes no hermes:** `tests/gateway/test_telegram_text_batching.py`
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/app/orchestrator.nim:662` (debounce adaptativo) e `tests/app/t_orchestrator.nim` (suite adaptive debounce collector)
- **Prioridade:** P2

### TG-015: Menções e /cmd@bot em grupos
- **Categoria:** INBOUND
- **Comportamento da API:** Em grupos, o bot recebe todas as mensagens quando a privacidade está desativada; comandos podem vir como `/cmd@botname`.
- **Gatilho / entrada:** Mensagem de grupo sem menção, ou comando endereçado ao bot.
- **Comportamento esperado do cliente:** Só agir quando mencionado (conforme configuração) e aceitar o sufixo @botname.
- **Fontes no hermes:** `1e18e0503f`, `3ff3dfb5ac`, `b0939d9210`
- **Testes no hermes:** `tests/gateway/test_telegram_mention_boundaries.py;tests/gateway/test_telegram_group_gating.py`
- **Situação no Donkey:** AUSENTE
- **Evidência no Donkey:** `rg -n "require_mention|@bot|mention" src/donkey/adapters/channel/telegram_runtime.nim` (sem resultados)
- **Prioridade:** P1

### TG-016: Remetente não autorizado é descartado antes do turno
- **Categoria:** INBOUND
- **Comportamento da API:** Updates de usuários fora da allowlist não devem gerar sessão nem resposta.
- **Gatilho / entrada:** Usuário desconhecido manda mensagem em DM ou grupo.
- **Comportamento esperado do cliente:** Aplicar a política de DM/allowlist antes de criar sessão.
- **Fontes no hermes:** `89d32052ed`, `db50af910b`, `c648ecdca5`
- **Testes no hermes:** `tests/gateway/test_telegram_group_gating.py`
- **Situação no Donkey:** PARCIAL
- **Evidência no Donkey:** `src/donkey/core/security/dm_policy.nim:18` e `src/donkey/app/session_ingress.nim` (checagem no ingress)
- **Prioridade:** P2

### TG-017: Todo toque em botão precisa de answerCallbackQuery
- **Categoria:** INBOUND
- **Comportamento da API:** Sem answerCallbackQuery o cliente mostra o botão girando por cerca de 30 s.
- **Gatilho / entrada:** Qualquer callback_query, inclusive desconhecido ou sem dados.
- **Comportamento esperado do cliente:** Responder sempre, mesmo quando o handler falha.
- **Fontes no hermes:** `ec092c80c1`, `f9de86c545`
- **Testes no hermes:** `tests/gateway/test_telegram_callback_ack.py`
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/adapters/channel/telegram.nim:442` e chamadas em `src/donkey/adapters/channel/telegram_runtime.nim:176`
- **Prioridade:** P2

### TG-018: Posts de canal e updates de negócio não são conversa
- **Categoria:** INBOUND
- **Comportamento da API:** `channel_post` e `business_message` chegam em campos diferentes de `message` e não representam uma DM do usuário.
- **Gatilho / entrada:** Post em canal ou mensagem de Telegram Business.
- **Comportamento esperado do cliente:** Ignorar esses updates em vez de responder aos contatos do dono.
- **Fontes no hermes:** `704872a62f`, `71b8408ae1`
- **Testes no hermes:** `tests/gateway/test_telegram_channel_posts.py`
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/domain/channels/telegram_pure.nim:123` (retorna tukUnknown)
- **Prioridade:** P2

### TG-019: Updates do mesmo chat mantêm a ordem
- **Categoria:** INBOUND
- **Comportamento da API:** getUpdates entrega updates em ordem crescente de update_id, e o offset precisa avançar para não reentregar.
- **Gatilho / entrada:** Mensagens rápidas no mesmo chat.
- **Comportamento esperado do cliente:** Processar em ordem e avançar o offset apenas após admitir o update.
- **Fontes no hermes:** `a6d7e08fd1`, `ff90457267`, `cbf6f6e7b3`
- **Testes no hermes:** -
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/domain/channels/telegram_pure.nim:165` (maxNextOffset) e inbox única em `src/donkey/app/session_ingress.nim`
- **Prioridade:** P2

### TG-020: 409 polling conflict exige nova tentativa com espera
- **Categoria:** NET
- **Comportamento da API:** Um segundo getUpdates simultâneo devolve 409 Conflict; o cliente deve parar o polling antigo e tentar de novo com espera.
- **Gatilho / entrada:** Reinício do processo ou duas instâncias durante o deploy.
- **Comportamento esperado do cliente:** Reconhecer o 409 e repetir com backoff, sem entrar em loop apertado.
- **Fontes no hermes:** `488a30e879`, `5a2fcaab39`, `f260aa6dc0`
- **Testes no hermes:** `tests/gateway/test_telegram_conflict.py`
- **Situação no Donkey:** PARCIAL
- **Evidência no Donkey:** `src/donkey/adapters/http/std_http.nim:70` (só status >= 500 são repetidos; 409 retorna direto)
- **Prioridade:** P1

### TG-021: Timeout de envio não pode duplicar a mensagem
- **Categoria:** NET
- **Comportamento da API:** Se a conexão cai depois de a requisição ser escrita, a API pode ter aceitado o sendMessage mesmo sem resposta.
- **Gatilho / entrada:** Timeout de rede durante o envio.
- **Comportamento esperado do cliente:** Não repetir cegamente um POST não idempotente; confirmar ou aceitar a perda.
- **Fontes no hermes:** `85cefc7a5a`, `e98a7006f8`
- **Testes no hermes:** `tests/gateway/test_send_retry.py`
- **Situação no Donkey:** AUSENTE
- **Evidência no Donkey:** `src/donkey/adapters/http/std_http.nim:29` (todo POST é repetido até maxRetries)
- **Prioridade:** P0

### TG-022: Proxy do ambiente é usado no transporte
- **Categoria:** NET
- **Comportamento da API:** A Bot API pode exigir proxy; as variáveis de ambiente do proxy precisam chegar ao cliente HTTP.
- **Gatilho / entrada:** Deploy atrás de proxy corporativo.
- **Comportamento esperado do cliente:** Aplicar o proxy configurado em todas as chamadas, sem vazar credenciais no log.
- **Fontes no hermes:** `d7c41f3cef`, `11e2e04667`, `aa7ee95c6c`
- **Testes no hermes:** -
- **Situação no Donkey:** PARCIAL
- **Evidência no Donkey:** `src/donkey/adapters/http/std_http.nim:21` (proxy opcional; o adapter do Telegram não o repassa)
- **Prioridade:** P2

### TG-023: Fallback de DNS não pode apontar para IP privado
- **Categoria:** NET
- **Comportamento da API:** Um resolvedor alternativo pode devolver IP privado ou loopback, que não pertence à Bot API.
- **Gatilho / entrada:** DNS comprometido ou mal configurado.
- **Comportamento esperado do cliente:** Recusar IPs privados/loopback no fallback.
- **Fontes no hermes:** `cdb64a869a`
- **Testes no hermes:** -
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/core/security/net_boundary.nim:11` (allowlist de hosts; o Donkey não usa DoH)
- **Prioridade:** P2

### TG-024: Webhook exige segredo
- **Categoria:** NET
- **Comportamento da API:** No modo webhook, a URL precisa de `secret_token` para validar a origem.
- **Gatilho / entrada:** Configuração de webhook.
- **Comportamento esperado do cliente:** Exigir e validar o segredo; sem ele, recusar o modo webhook.
- **Fontes no hermes:** `16accd44bd`
- **Testes no hermes:** `tests/gateway/test_telegram_webhook_secret.py`
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `rg -n "webhook" src/donkey` (sem resultados; o Donkey usa apenas long polling)
- **Prioridade:** P2

### TG-025: Forum topics exigem message_thread_id
- **Categoria:** TOPIC_API
- **Comportamento da API:** Mensagens em um forum topic precisam de `message_thread_id`; sem ele a resposta cai no tópico geral.
- **Gatilho / entrada:** Chat com tópicos habilitados.
- **Comportamento esperado do cliente:** Propagar o thread id do update até o envio e a edição.
- **Fontes no hermes:** `928bb16da1`, `a630ca15de`, `2564132a1f`
- **Testes no hermes:** `tests/gateway/test_telegram_thread_fallback.py`
- **Situação no Donkey:** AUSENTE
- **Evidência no Donkey:** `rg -n "message_thread_id|thread_id" src/donkey` (sem resultados)
- **Prioridade:** P1

### TG-026: "Message thread not found" cai para o chat raiz
- **Categoria:** TOPIC_API
- **Comportamento da API:** Um thread id inválido ou apagado devolve 400 "message thread not found".
- **Gatilho / entrada:** Tópico apagado ou thread id obsoleto.
- **Comportamento esperado do cliente:** Reenviar sem o thread id para não perder a mensagem.
- **Fontes no hermes:** `41d9d08078`, `ae005ec588`, `d385936a97`
- **Testes no hermes:** `tests/gateway/test_telegram_thread_fallback.py`
- **Situação no Donkey:** AUSENTE
- **Evidência no Donkey:** `rg -n "thread not found" src/donkey` (sem resultados)
- **Prioridade:** P1

### TG-027: Foto fora dos limites vira documento
- **Categoria:** MEDIA
- **Comportamento da API:** sendPhoto recusa dimensões ou tamanho acima do limite; sendDocument aceita o mesmo arquivo.
- **Gatilho / entrada:** Imagem grande ou com proporção inválida.
- **Comportamento esperado do cliente:** Cair para sendDocument em vez de perder a mídia.
- **Fontes no hermes:** `69fc6d9c1e`, `f6aa1965d7`, `542faf225f`
- **Testes no hermes:** -
- **Situação no Donkey:** AUSENTE
- **Evidência no Donkey:** `src/donkey/adapters/channel/telegram.nim:142` (escolhe por extensão; o fallback é enviar a URL como texto)
- **Prioridade:** P1

### TG-028: Álbuns chegam como updates separados com media_group_id
- **Categoria:** MEDIA
- **Comportamento da API:** Um álbum é entregue como várias mensagens com o mesmo `media_group_id`, sem garantia de chegada em uma única chamada.
- **Gatilho / entrada:** Usuário envia várias fotos de uma vez.
- **Comportamento esperado do cliente:** Agrupar pelo media_group_id e tratar o conjunto como uma entrada.
- **Fontes no hermes:** `8fb618234f`, `4ae1334287`, `c7af0fcadc`
- **Testes no hermes:** `tests/gateway/test_telegram_documents.py`
- **Situação no Donkey:** PARCIAL
- **Evidência no Donkey:** `rg -n "media_group_id" src/donkey` (sem resultados); o debounce em `src/donkey/app/orchestrator.nim:662` preserva só a última mídia
- **Prioridade:** P1

### TG-029: Voz e áudio têm metadados próprios
- **Categoria:** MEDIA
- **Comportamento da API:** sendVoice/sendAudio aceitam `duration`; sem ele o cliente mostra 0:00. Voz usa OGG/OPUS.
- **Gatilho / entrada:** Envio de nota de voz ou faixa de áudio.
- **Comportamento esperado do cliente:** Enviar duração e formato adequados ao tipo.
- **Fontes no hermes:** `27364b24fe`, `ae82eed2b1`, `b93996c35e`
- **Testes no hermes:** `tests/gateway/test_telegram_audio_vs_voice.py;tests/gateway/test_auto_voice_reply_format.py`
- **Situação no Donkey:** AUSENTE
- **Evidência no Donkey:** `rg -n "sendVoice|sendAudio|duration" src/donkey/adapters/channel/telegram.nim` (sem resultados)
- **Prioridade:** P2

### TG-030: Upload de mídia precisa de prazo próprio
- **Categoria:** MEDIA
- **Comportamento da API:** Uploads grandes demoram mais que o timeout padrão de texto.
- **Gatilho / entrada:** Envio de vídeo ou arquivo grande.
- **Comportamento esperado do cliente:** Aplicar um prazo maior apenas aos uploads.
- **Fontes no hermes:** `85e673b4a5`, `04057250a3`
- **Testes no hermes:** `tests/gateway/test_telegram_send_path_health.py`
- **Situação no Donkey:** PARCIAL
- **Evidência no Donkey:** `src/donkey/adapters/http/std_http.nim:19` (timeout único de 60 s para todas as chamadas)
- **Prioridade:** P2

### TG-031: Finalização atrasada não pode suprimir a resposta final
- **Categoria:** EDIT
- **Comportamento da API:** Uma edição de finalização que chega depois de outra pode apagar ou suprimir o texto final se o cliente confiar em estado obsoleto.
- **Gatilho / entrada:** Streaming com edições concorrentes.
- **Comportamento esperado do cliente:** Só considerar a resposta entregue quando a edição final for confirmada.
- **Fontes no hermes:** `30878411b8`, `fab36436b2`, `0cc7f79016`
- **Testes no hermes:** `tests/gateway/test_stream_consumer.py`
- **Situação no Donkey:** PARCIAL
- **Evidência no Donkey:** `src/donkey/app/outbound_runtime.nim` (estado de apresentação; sem confirmação de edição final)
- **Prioridade:** P1

### TG-032: Reação só aceita emojis permitidos pelo chat
- **Categoria:** EDIT
- **Comportamento da API:** setMessageReaction recusa emojis fora de `available_reactions` com "reaction_invalid".
- **Gatilho / entrada:** Chat com reações restritas.
- **Comportamento esperado do cliente:** Escolher um emoji da lista permitida e ignorar a recusa.
- **Fontes no hermes:** `0e315a6f02`, `52b3a3ca3a`
- **Testes no hermes:** `tests/gateway/test_telegram_reactions.py`
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/adapters/channel/telegram.nim:78` (pickTelegramReactionEmoji) e `:312`
- **Prioridade:** P2

### TG-033: Code fences: CRLF, aninhamento e fences no meio da linha
- **Categoria:** FORMAT
- **Comportamento da API:** Blocos de código usam três ou mais crases; o fechamento pode vir com CRLF e crases aninhadas não devem ser confundidas com o delimitador.
- **Gatilho / entrada:** Resposta com código, especialmente vinda de modelos que usam CRLF.
- **Comportamento esperado do cliente:** Reconhecer o fence pelo tamanho da sequência de crases e aceitar CRLF.
- **Fontes no hermes:** `3480de0402`, `5f7b1e2d65`, `6c1e913bb0`, `8518913cff`
- **Testes no hermes:** -
- **Situação no Donkey:** PARCIAL
- **Evidência no Donkey:** `src/donkey/core/telegram_format.nim:65` (procura literal "```" e não trata CRLF)
- **Prioridade:** P1

### TG-034: Tabelas não existem no HTML do Telegram
- **Categoria:** FORMAT
- **Comportamento da API:** O Telegram não renderiza tabelas HTML; a sintaxe precisa virar texto.
- **Gatilho / entrada:** Resposta com tabela Markdown.
- **Comportamento esperado do cliente:** Converter linhas de tabela em texto legível.
- **Fontes no hermes:** `8fdaf4d3d6`, `9d10c45e32`
- **Testes no hermes:** -
- **Situação no Donkey:** COBERTO
- **Evidência no Donkey:** `src/donkey/core/telegram_format.nim:206` (converte tabela em linhas com " • ")
- **Prioridade:** P2

### TG-035: Prévia de link pode ser desativada
- **Categoria:** FORMAT
- **Comportamento da API:** sendMessage aceita `link_preview_options.is_disabled`; sem isso a API gera prévia para a primeira URL.
- **Gatilho / entrada:** Mensagem com URL que não deve gerar cartão.
- **Comportamento esperado do cliente:** Desativar a prévia quando o conteúdo é técnico ou repetitivo.
- **Fontes no hermes:** `f6cfbd2b16`, `00ff9a26cd`
- **Testes no hermes:** `tests/gateway/test_telegram_text_link_expansion.py`
- **Situação no Donkey:** AUSENTE
- **Evidência no Donkey:** `rg -n "link_preview" src/donkey` (sem resultados)
- **Prioridade:** P2

### TG-036: Menu de comandos tem limites de quantidade e tamanho
- **Categoria:** FORMAT
- **Comportamento da API:** setMyCommands aceita até 100 comandos, com nomes de até 32 caracteres e descrições de até 40; acima do limite a chamada falha.
- **Gatilho / entrada:** Publicação do menu de comandos do bot.
- **Comportamento esperado do cliente:** Truncar nomes/descrições e limitar a quantidade antes de publicar.
- **Fontes no hermes:** `60ecde8ac7`, `da3e22bcfa`, `2ae50bdddd`
- **Testes no hermes:** -
- **Situação no Donkey:** AUSENTE
- **Evidência no Donkey:** `rg -n "setMyCommands" src/donkey` (sem resultados)
- **Prioridade:** P2

### TG-037: Escape de MarkdownV2 e de HTML
- **Categoria:** FORMAT
- **Comportamento da API:** MarkdownV2 exige escape de 18 caracteres reservados; HTML exige escapar `<`, `>` e `&`.
- **Gatilho / entrada:** Texto dinâmico (nomes, URLs, saída de ferramenta) enviado com formatação.
- **Comportamento esperado do cliente:** Escapar o texto dinâmico antes de montar a mensagem.
- **Fontes no hermes:** `55c70f3508`, `a56937735e`, `a694040520`
- **Testes no hermes:** -
- **Situação no Donkey:** PARCIAL
- **Evidência no Donkey:** `src/donkey/core/telegram_format.nim:13` (escapa HTML; o Donkey não usa MarkdownV2)
- **Prioridade:** P1

## Resumo

| Categoria | Situação | Prioridade | Casos |
|---|---|---|---|
| EDIT | AUSENTE | P0 | 1 |
| EDIT | AUSENTE | P1 | 1 |
| EDIT | COBERTO | P2 | 1 |
| EDIT | PARCIAL | P1 | 1 |
| FORMAT | AUSENTE | P0 | 1 |
| FORMAT | AUSENTE | P1 | 1 |
| FORMAT | AUSENTE | P2 | 2 |
| FORMAT | COBERTO | P2 | 1 |
| FORMAT | PARCIAL | P1 | 3 |
| INBOUND | AUSENTE | P0 | 3 |
| INBOUND | AUSENTE | P1 | 1 |
| INBOUND | COBERTO | P2 | 4 |
| INBOUND | PARCIAL | P2 | 1 |
| MEDIA | AUSENTE | P1 | 2 |
| MEDIA | AUSENTE | P2 | 1 |
| MEDIA | PARCIAL | P1 | 1 |
| MEDIA | PARCIAL | P2 | 1 |
| NET | AUSENTE | P0 | 1 |
| NET | COBERTO | P2 | 2 |
| NET | PARCIAL | P1 | 1 |
| NET | PARCIAL | P2 | 1 |
| RATE | AUSENTE | P1 | 1 |
| RATE | COBERTO | P2 | 1 |
| RATE | PARCIAL | P1 | 1 |
| RATE | PARCIAL | P2 | 1 |
| TOPIC_API | AUSENTE | P1 | 2 |

| Total de casos | 37 |
|---|---|
| COBERTO | 9 |
| PARCIAL | 11 |
| AUSENTE | 17 |
| P0 | 6 |
| P1 | 15 |
| P2 | 16 |
