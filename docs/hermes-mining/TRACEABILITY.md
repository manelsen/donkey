# Rastreabilidade — casos do hermes no Donkey

Uma linha por caso P0 de [`telegram/CASES.md`](telegram/CASES.md). O status
começa em `pendente` e passa a `portado` quando o teste e a implementação
existem; `adiado` registra o motivo quando o caso não pode ser portado nesta
rodada.

| Caso | Commits hermes | Teste Donkey | Implementação Donkey | Status |
|---|---|---|---|---|
| TG-001 | `9e992df8ae`, `b7c4369ca0`, `c0da5d09a6`, `022d196f38` | `tests/domain/channels/t_telegram_split.nim` | `src/donkey/domain/channels/telegram_split.nim` | portado |
| TG-002 | `7ac9088d5c`, `6483c39f84` | `tests/domain/channels/t_telegram_policy.nim` | `src/donkey/domain/channels/telegram_policy.nim` | portado |
| TG-003 | `fbfe294882`, `6fb25f86ac`, `3a37785f7f` | `tests/domain/channels/t_telegram_pure.nim` | `src/donkey/domain/channels/telegram_pure.nim` | portado |
| TG-004 | `1a9a2d7fe8`, `c419cf7c86`, `704872a62f` | `tests/domain/channels/t_telegram_pure.nim` | `src/donkey/domain/channels/telegram_pure.nim` | portado |
| TG-005 | `b60cfd6ce6`, `713e2274cf`, `29cda7a5ef` | `tests/domain/channels/t_telegram_policy.nim` | `src/donkey/domain/channels/telegram_policy.nim` | portado |
| TG-021 | `85cefc7a5a`, `e98a7006f8` | `tests/http/t_std_http.nim` | `src/donkey/adapters/http/std_http.nim` | portado |

## Discord

Os casos do Discord são numerados à medida que são portados; a classificação
completa dos 407 commits ainda não foi feita (ver `discord/SCOPE.md`).

| Caso | Commits hermes | Teste Donkey | Implementação Donkey | Status |
|---|---|---|---|---|
| DS-001 | `cee761ee4a`, `807bdc17f6` | `tests/channel/t_discord.nim`, `tests/adapters/channel/t_requester_only_send_paths.nim` | `src/donkey/adapters/channel/discord.nim` (`isDuplicateMessage`) | portado |
| DS-002 | `2278f2cb7e` | `tests/adapters/channel/t_requester_only_send_paths.nim` | `src/donkey/adapters/channel/discord.nim` (`deResync`) | portado |
| DS-003 | `efa6c9f715` | `tests/domain/channels/t_discord_pure.nim`, `tests/adapters/channel/t_requester_only_send_paths.nim` | `src/donkey/domain/channels/discord_pure.nim` (`withSafeMentions`) | portado |
| DS-004 | `68276773cf` | `tests/domain/channels/t_discord_pure.nim` | `src/donkey/domain/channels/discord_pure.nim` (`isBotAuthored`) | portado |
| DS-005 | `93ea9b04af` | `tests/domain/channels/t_discord_pure.nim` | `src/donkey/domain/channels/discord_pure.nim` (`DiscordMaxInboundAttachmentBytes`) | portado |
| DS-006 | `cf7bf5bdc9` | `tests/domain/channels/t_discord_pure.nim`, `tests/adapters/channel/t_requester_only_send_paths.nim` | `src/donkey/domain/channels/discord_pure.nim` (`discordText`) | portado |
| DS-007 | `608e8a6062`, `e9bceb5ae0` | `tests/domain/channels/t_discord_pure.nim`, `tests/adapters/channel/t_requester_only_send_paths.nim` | `src/donkey/domain/channels/discord_pure.nim` (`addressesBot`, `stripBotMention`), `src/donkey/adapters/channel/discord_runtime.nim` | portado |
| DS-008 | `9a177d6f4b`, `53da34a4fc` | `tests/channel/t_discord.nim`, `tests/domain/channels/t_discord_pure.nim`, `tests/adapters/channel/t_requester_only_send_paths.nim` | `src/donkey/adapters/channel/discord.nim` (`messageEventOf`, `downloadFile`), `src/donkey/adapters/channel/discord_runtime.nim` | portado |
| DS-009 | `020ef76cf1` (no hermes o resto vem do discord.py; aqui é o contrato do gateway) | `tests/domain/channels/t_discord_pure.nim` | `src/donkey/domain/channels/discord_pure.nim` (`heartbeatStep`, `closeAction`), `src/donkey/adapters/channel/discord.nim` (gateway) | portado |
| DS-010 | `5a3cadf6eb` (cluster de rate limit; o formato do 429 e o `nonce` são contrato da API do Discord) | `tests/http/t_std_http.nim`, `tests/adapters/channel/t_requester_only_send_paths.nim` | `src/donkey/adapters/http/std_http.nim` (`rateLimitWaitMs`), `src/donkey/adapters/channel/discord.nim` (`withNonce`) | portado |
| DS-011 | `8598746e86`, `f6d4b6a319` | `tests/domain/channels/t_discord_pure.nim`, `tests/adapters/channel/t_requester_only_send_paths.nim` | `src/donkey/domain/channels/discord_pure.nim` (`discordChannelAllowed`), `src/donkey/adapters/channel/discord_runtime.nim` | portado |

## Slack

Casos portados avulsos; o Slack ainda não tem extração nem triagem própria.

| Caso | Commits hermes | Teste Donkey | Implementação Donkey | Status |
|---|---|---|---|---|
| SL-001 | `38863322a4` | `tests/domain/channels/t_slack_pure.nim`, `tests/adapters/channel/t_requester_only_send_paths.nim` | `src/donkey/domain/channels/slack_pure.nim` (`neutralizeBroadcastMentions`, `withoutBroadcastMentions`), `src/donkey/adapters/channel/slack.nim` (`postJson`, `respondToUrl`) | portado |
