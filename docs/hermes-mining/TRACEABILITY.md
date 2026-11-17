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
| TG-021 | `85cefc7a5a`, `e98a7006f8` | - | - | adiado (repetição de POST não idempotente exige mudança em `ports/http`) |
