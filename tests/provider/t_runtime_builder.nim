import std/unittest
import donkey/adapters/provider/runtime_builder
import donkey/core/pipeops
import donkey/domain/message
import donkey/ports/provider

suite "runtime_builder fallback":

  test "fallbackOnError keeps primary response when primary succeeds":
    var fallbackCalls = 0
    let primary: CompleteFn =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        ok(CompletionResponse(text: "primary"))
    let fallback: CompleteFn =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        inc fallbackCalls
        ok(CompletionResponse(text: "fallback"))

    let resp = fallbackOnError(primary, fallback)(CompletionRequest())
    check resp.isOk
    check resp.get().text == "primary"
    check fallbackCalls == 0

  test "fallbackOnError uses fallback when primary fails":
    var fallbackCalls = 0
    let primary: CompleteFn =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        err("primary failed")
    let fallback: CompleteFn =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        inc fallbackCalls
        ok(CompletionResponse(text: "fallback"))

    let resp = fallbackOnError(primary, fallback)(CompletionRequest())
    check resp.isOk
    check resp.get().text == "fallback"
    check fallbackCalls == 1

  test "fallbackOnError preserves primary error when fallback is nil":
    let primary: CompleteFn =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        err("primary failed")

    let resp = fallbackOnError(primary, nil)(CompletionRequest())
    check resp.isErr
    check resp.error == "primary failed"
