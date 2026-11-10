## Streaming tool-call contract tests.

import std/[strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/app/tool_loop_runtime
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/provider

suite "streamToOutbox — tool calls":

  test "returns tool calls and does not emit a fake final text":
    let fn: StreamFn = proc(req: CompletionRequest;
                            onToken: proc(tok: string) {.gcsafe.}
                           ): Result[CompletionResponse, string] {.gcsafe.} =
      onToken("partial")
      ok(CompletionResponse(
        text: "partial",
        toolCalls: @[ToolCallRequest(id: "call_1", name: "read_file", inputJson: "{}")],
      ))

    let outbox = newAsyncQueue[OutboundMessage]()
    let res = waitFor streamToOutbox(
      fn, CompletionRequest(), outbox, UserId("u1"), ckTelegram, "", "sid")
    check res.isOk
    check res.value.toolCalls.len == 1
    check res.value.toolCalls[0].name == "read_file"
    check outbox.len == 0

  test "provider error is returned instead of a fake final message":
    let fn: StreamFn = proc(req: CompletionRequest;
                            onToken: proc(tok: string) {.gcsafe.}
                           ): Result[CompletionResponse, string] {.gcsafe.} =
      err("HTTP 500")

    let outbox = newAsyncQueue[OutboundMessage]()
    let res = waitFor streamToOutbox(
      fn, CompletionRequest(), outbox, UserId("u1"), ckTelegram, "", "sid")
    check res.isErr
    check "HTTP 500" in res.error
    check outbox.len == 0

  test "text-only stream still emits the final message":
    let fn: StreamFn = proc(req: CompletionRequest;
                            onToken: proc(tok: string) {.gcsafe.}
                           ): Result[CompletionResponse, string] {.gcsafe.} =
      onToken("hello")
      ok(CompletionResponse(text: "hello"))

    let outbox = newAsyncQueue[OutboundMessage]()
    let res = waitFor streamToOutbox(
      fn, CompletionRequest(), outbox, UserId("u1"), ckTelegram, "", "sid")
    check res.isOk
    check res.value.toolCalls.len == 0
    check outbox.len == 1
    let final = waitFor outbox.get()
    check final.text == "hello"
    check final.isPartial == false
