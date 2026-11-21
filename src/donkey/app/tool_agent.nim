## ToolAgent — actor responsible for MCP/Deno tool invocations.
##
## Inbox messages (amkTask):
##   taskKind="invokeTool" → payload is JSON: {name, id, inputJson, userInterrupt}
##                           tries each registered client in order
##                           replies with amkResult(text=output) or amkError
##
## Stops on amkCancel.
##
## Adapters with an async entry point can release the actor on a turn interrupt.

import std/json
import chronos
import chronos/asyncsync
import ../core/pipeops
import ../domain/agent_message
import ../ports/tool
import ./session_manager

func interruptedTool(call: ToolCall): Result[ToolResult, string] =
  ok(ToolResult(callId: call.id, output: "Error: tool invocation interrupted.",
                isError: true))

proc awaitAsyncTool(client: ToolRuntimePort; call: ToolCall;
                    interrupt: uint64): Future[Result[ToolResult, string]] {.async.} =
  let pending = client.invokeAsync(call)
  try:
    while not pending.finished():
      if daemonShuttingDown() or isUserStoppedSince(call.userId, interrupt):
        return interruptedTool(call)
      await sleepAsync(milliseconds(25))
    return pending.read()
  finally:
    if not pending.finished():
      await pending.cancelAndWait()

proc runToolAgent*(inbox:   AsyncQueue[AgentMessage];
                   outbox:  AsyncQueue[AgentMessage];
                   clients: seq[ToolRuntimePort]): Future[void] {.async.} =
  while true:
    let msg = await inbox.get()
    case msg.kind

    of amkCancel:
      break

    of amkTask:
      if msg.taskKind != tkInvokeTool:
        await outbox.put(newErrorMsg(msg.id, "ToolAgent: unexpected task: " & $msg.taskKind))
        continue

      var toolName  = ""
      var toolId    = ""
      var toolInput = newJObject()
      var interrupt = currentUserInterrupt(msg.userId)
      try:
        let j    = parseJson(msg.payload)
        toolName  = j["name"].getStr("")
        toolId    = j["id"].getStr("")
        interrupt = j{"userInterrupt"}.getBiggestInt(interrupt.BiggestInt).uint64
        toolInput = try: parseJson(j["inputJson"].getStr("{}"))
                    except CatchableError: newJObject()
      except CatchableError as e:
        await outbox.put(newErrorMsg(msg.id, "ToolAgent: bad payload: " & e.msg))
        continue

      let call = ToolCall(id: toolId, name: toolName, input: toolInput,
                            userId: msg.userId)

      var invoked = false
      for client in clients:
        let res: Result[ToolResult, string] =
          try:
            if daemonShuttingDown() or isUserStoppedSince(call.userId, interrupt):
              interruptedTool(call)
            elif client.invokeAsync != nil:
              await awaitAsyncTool(client, call, interrupt)
            elif client.invoke != nil:
              client.invoke(call)
            else:
              Result[ToolResult, string].err("tool invocation unavailable")
          except CancelledError:
            raise
          except Exception as e:  ## effect boundary: callee raises are unannotated
            Result[ToolResult, string].err("ToolAgent invoke: " & e.msg)
        if res.isOk:
          await outbox.put(newResultMsg(msg.id, res.value.output))
          invoked = true
          break

      if not invoked:
        await outbox.put(newErrorMsg(msg.id,
          "Tool '" & toolName & "' not found in any registered server."))

    else:
      discard
