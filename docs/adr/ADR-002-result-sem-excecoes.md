# ADR-002 — Result[T, E] + sem exceções em adapters

**Status:** Aceito
**Data:** 2025 (F0)

## Contexto

Adapters fazem I/O fallível (HTTP, arquivos, processos). Decidir como reportar falhas.

## Decisão

Todo I/O fallível retorna `Result[T, string]`. Exceções (`raise`/`try`) são proibidas em adapters e na camada de aplicação. `try/except` existe apenas **dentro** do adapter, nunca exposto.

O módulo `donkey/core/pipeops` exporta `results` + operadores `|>` e `>>=`. O resto do codebase importa via `pipeops` — nunca `results` diretamente.

```nim
# Adapter absorve a exceção — nunca expõe
proc complete*(a: ZhipuAdapter; req: CompletionRequest): Result[CompletionResponse, string] =
  try:
    ok(CompletionResponse(...))
  except CatchableError as e:
    err(e.msg)

# Caller propaga com ?
proc runTurn*(...): Result[string, string] =
  let resp = ? runner.provider.complete(req)
  ok(resp.text)

# Loop principal: valueOr / isOkOr para terminação local
let msgs = channel.receive().valueOr:
  log.error("receive: " & error); continue

# Pipeline puro: |>
let context = (ctx.memoryMd & "\n" & ctx.preferencesMd) |> strip

# Railway-oriented: >>=
provider.complete(req) >>= saveToMemory >>= notifyUser
```

## Racional

- Torna erros explícitos e rastreáveis em compile-time.
- Procs do domínio (`func`) continuam puros — sem Result, sem I/O.
- Composição funcional com `?`, `>>=`, `|>` em vez de try/catch aninhados.
- Consistente com a filosofia "functional core, effectful shell".

## Consequências

- Adapters são mais verbosos (always wrap em try/except interno).
- Stack traces perdem informação de origem quando o erro é stringificado — aceitável para o caso de uso.
- `?` exige que o tipo de retorno seja `Result[_, _]` — força disciplina na assinatura de procs.
