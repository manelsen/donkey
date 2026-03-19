# ADR-001 — Nim + Chronos (não asyncdispatch)

**Status:** Aceito
**Data:** 2025 (F0)

## Contexto

Donkey precisa de I/O assíncrono para múltiplos canais, providers e workers de agente concorrentes. Nim tem dois sistemas async: `asyncdispatch` (stdlib) e `Chronos` (Status Research).

## Decisão

Usar **Chronos** como runtime async em todo o projeto. `asyncdispatch` não é usado em nenhum módulo.

## Racional

| | asyncdispatch | Chronos |
|--|---|---|
| Cancelamento | `Future.cancel()` best-effort | `cancelSoon()` + structured concurrency |
| Error propagation | Exceções escapam silenciosamente | `raises:` enforced, erros tipados |
| Structured concurrency | Não tem | `AsyncQueue`, `AsyncEvent`, barriers |
| Interop com stdlib | Direto | Adaptadores necessários para stdlib blocking |
| Uso em produção | Nim stdlib | nim-libp2p, Nimbus, Status apps |

Cancelamento nativo é crítico para abort em cascata dos workers de agente. Error propagation correto elimina exceções silenciosas em procs async.

## Consequências

### Conhecidas

- `{.async.}` de Chronos gera procs com `raises: [CatchableError]` por padrão — restringe chamadas.
- Procs `{.async.}` exigem `{.gcsafe.}` em tudo que chamam.
- `result =` e `err(v)`/`ok(v)` dentro de void async causam conflito com templates do macro Chronos — usar variáveis locais + `return`.
- `asyncSpawn` de código sync: coroutine começa até o primeiro `await`; resto roda no próximo `waitFor`.
- Para procs que precisam chamar `Exception` (não `CatchableError`): `{.async: (raises: [Exception]).}`.

### Irreversível

Mudar para asyncdispatch ou outro runtime exigiria reescrever toda a camada de aplicação.
