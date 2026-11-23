# Escopo — mineração do Discord

> **Estado:** triagem inicial. A classificação commit a commit e os casos
> consolidados são o passo seguinte; este documento só mede o corpus e
> identifica o primeiro alvo.

## Escopo da extração

- `HERMES_REF`: `b076b5856cc6b74ab815ea97d866ee5022a5282a` (`HEAD` do hermes
  na data desta rodada; o SHA completo está em `LAST_SYNC`).
- Commits extraídos: **407** (união de assuntos `fix.*discord` com os fixes que
  tocam `plugins/platforms/discord` e `gateway/platforms/discord.py`).
- Commits que tocam teste: **322 de 407** (79%).
- Pipeline: `HERMES_REF=HEAD bash scripts/hermes_mine.sh discord`; duas
  execuções produzem `commits.tsv` byte-idêntico.
- Nenhum código do hermes é copiado: o que se transfere é o comportamento
  documentado nos commits, como no piloto do Telegram.

Para comparação, o Telegram rendeu 718 commits com a ref pinada em
`b3746e35dd`. O Discord é ~57% desse volume e tem a mesma proporção de commits
com teste.

## Triagem por assunto

Contagem de **menções no assunto**, não categorias exclusivas: um commit pode
aparecer em mais de uma linha. Serve para dimensionar o trabalho, não para
classificar.

| Cluster | Commits | Observação |
|---|---:|---|
| Conexão/reconexão/gateway | 123 | inclui intents, startup/shutdown, heartbeat, proxy |
| Auth/aprovação/permissão | 91 | inclui slash commands de aprovação e PII |
| Slash/commands/interações | 61 | registro, autocomplete, deferred, botões |
| Menção/reply/inbound | 51 | inclui dedup e batching |
| Voz (Opus/RTP/STT/TTS) | 45 | maior custo de porte; depende de stack de áudio |
| Threads | 41 | participação, persistência, slash em thread |
| Mídia/anexos/emoji | 40 | documento, vídeo, limites de upload |
| Entrega/recovery/cursor/dedup | 36 | o cluster P0 deste canal |
| Rate limit/429/retry | 11 | inclui tempestade de edits |

## Primeiro alvo: entrega e recuperação

É o cluster que mais se parece com o que o Telegram ensinou: perda ou
duplicação de mensagem em reconexão. O hermes acumulou uma camada inteira
sobre o gateway:

| Commit | Comportamento documentado |
|---|---|
| `bc0e5adb1d` | cursor de recuperação persistido por canal |
| `2b2203e3a7` | cursor só avança depois da entrega final |
| `9412f2dd84` | entrega final streamada é persistida |
| `d5b9c1ee37` | claim de recuperação e falha do ledger são guardados |
| `38b39b87ef` | I/O do ledger de recuperação fora do event loop |
| `2278f2cb7e` | recuperação de mensagens endurecida na reconexão |
| `80744bc2bc`, `fad6cbaed3` | bordas de ciclo de vida da reconexão |
| `da955a643e` | identidade da mensagem de recuperação preservada |
| `8c6881231a` | backfill não re-despacha turno já entregue |
| `cee761ee4a`, `807bdc17f6` | dedup de gateway e de thread-starter |
| `b9ec39939b` | dedup pré-semeado antes do `mark_async` |
| `2e2212be1b` | dedup de previews saturados para parar tempestade de edits |

### O que o Donkey tem hoje

`src/donkey/adapters/channel/discord.nim` mantém `session_id`, `seq` e
`resume_gateway_url` e retoma a sessão no gateway. Desde esta triagem:

- **Cursor por usuário** (`discord_last_msg_id` nas preferências) e
  **backfill de DMs no startup** (`checkDiscordOfflineMessages`), que filtra
  pelo cursor e, sem cursor nem relógio de sessão, marca o histórico como visto
  em vez de reprocessá-lo.
- **Dedup de mensagem** (`isDuplicateMessage`, janela de 10 min, até 2048 ids,
  em `core/channels/recent_ids`, o mesmo tipo do Slack): o replay de um RESUME
  e a sobreposição do backfill com o tempo real não re-despacham um turno
  (cobre `cee761ee4a`/`807bdc17f6`).

- **Backfill depois de uma sessão perdida**: um READY depois de outro no
  mesmo processo (RESUME recusado ou impossível) põe `deResync` na fila, e o
  drain roda a mesma recuperação do startup (cobre `2278f2cb7e`).

- **Menções seguras** (`withSafeMentions`): toda mensagem que o bot envia ou
  edita leva `allowed_mentions: {parse: ["users"]}`; um `@everyone` ou menção
  de cargo no texto do modelo não notifica ninguém (`efa6c9f715`).
- **Webhooks como bots** (`isBotAuthored`): post de webhook não dispara turno,
  nem no tempo real nem no backfill (`68276773cf`).
- **Teto de anexo recebido** (25 MiB, pelo `size` do evento): o anexo maior
  não é baixado; o turno recebe uma nota com o nome do arquivo (`93ea9b04af`).

- **Tabelas** (`discordText`): o Discord não renderiza tabela GFM; cada linha
  vira um bloco com a primeira célula em negrito e as outras como
  `• Cabeçalho: valor`, fora de blocos de código (`cf7bf5bdc9`).

- **Menção em servidor** (`addressesBot`, `stripBotMention`): a menção crua
  do bot sai do texto antes do despacho (`<@bot> /help` é o comando `/help`) e
  um ping só com a menção é ignorado. Com `DONKEY_DISCORD_REQUIRE_MENTION`
  (opt-in, como no Telegram), só mensagem que menciona o bot ou responde a ele
  é atendida; DM não muda. O array `mentions` não conta: um reply ping põe o
  autor ali sem menção no texto (`608e8a6062`, `e9bceb5ae0`).

- **Anexos recebidos chegam ao turno**: o primeiro anexo (URL, nome e tipo)
  vai no `InboundMessage` e é baixado como nos outros canais; os demais são
  nomeados no texto. O backfill monta o evento pelo mesmo parser, então anexo
  enviado com o bot offline (inclusive sem texto) também é recuperado. O
  download só sai para `cdn.discordapp.com`/`media.discordapp.net` por https
  (`9a177d6f4b`, `53da34a4fc`).

- **Vida do gateway** (`heartbeatStep`, `closeAction`): heartbeat sem ACK até
  o próximo fecha a conexão e retoma a sessão (antes, um socket meio aberto
  deixava o bot mudo para sempre); op 1 é respondido na hora; close 4004 e
  4010–4014 param o gateway em vez de reconectar em laço; 4007/4009 abrem
  sessão nova. O socket é fechado ao fim de cada sessão (vazava um por
  reconexão). No hermes isso vem do discord.py; aqui é o contrato do gateway.

Ainda **não há**: ledger de entrega e cursor que só avança depois da entrega
final (hoje avança antes do despacho: at-most-once).

O Slack já tem um precedente interno de dedup com TTL
(`tests/channel/t_slack.nim`, suíte "SlackAdapter event deduplication"), então
o porte não precisa inventar o formato do registro.

## O que esta triagem não decide

- **Voz** é o maior bloco isolado e depende de RTP/Opus/STT; provavelmente
  merece um balde próprio, depois dos P0 de entrega.
- **Slash commands**: o Donkey trata comandos no texto da mensagem; registrar
  comandos nativos no Discord é decisão de produto, não só correção.
- **Auth/aprovação** é grande, mas parte é UI de botões que o Donkey já tem
  em outros canais; precisa da classificação para separar o que é contrato da
  API do que é escolha do hermes.

## Próximos passos

1. Classificar os 407 commits em `classification.tsv` (categoria,
   transferível, motivo), com `UNCLEAR` abaixo de 5%.
2. Consolidar os transferíveis em casos numerados (`DS-001`…), com prioridade
   P0/P1/P2 pela mesma regra do Telegram.
3. Portar primeiro o cluster de entrega/recuperação, escrevendo o teste antes
   e registrando caso → commit → teste em `TRACEABILITY.md`.
