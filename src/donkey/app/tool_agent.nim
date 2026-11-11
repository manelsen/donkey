## ToolAgent — actor responsible for MCP/Deno tool invocations.
##
## Inbox messages (amkTask):
##   taskKind="invokeTool" → payload is JSON: {name, id, inputJson}
##                           tries each registered client in order
##                           replies with amkResult(text=output) or amkError
##
## Stops on amkCancel.
##
## NOTE: tool invocations are blocking (subprocess I/O). This is acceptable
## for F4 since the Chronos event loop is cooperative and single-user sessions
## are sequential. True async tool execution requires async subprocess I/O (F5+).

import std/json
import chronos
import chronos/asyncsync
import ../domain/agent_message
import ../ports/tool

proc runToolAgent*(inbox:   AsyncQueue[AgentMessage];
                   outbox:  AsyncQueue[AgentMessage];
                   clients: seq[ToolRuntimePort]): Future[void] {.async.} =
  var liveClients = clients  ## local mutable copy

  while true:
    let msg = await inbox.get()
    case msg.kind

    of amkCancel:
      break

    of amkTask:
      if msg.taskKind != tkInvokeTool:
        await outbox.put(newErrorMsg(msg.id, "ToolAgent: unexpected task: " & $msg.taskKind))
        continue

      ## Parse payload: {name, id, inputJson}
      var toolName  = ""
      var toolId    = ""
      var toolInput = newJObject()
      try:
        let j    = parseJson(msg.payload)
        toolName  = j["name"].getStr("")
        toolId    = j["id"].getStr("")
        toolInput = try: parseJson(j["inputJson"].getStr("{}"))
                    except: newJObject()
      except CatchableError as e:
        await outbox.put(newErrorMsg(msg.id, "ToolAgent: bad payload: " & e.msg))
        continue

      let call = ToolCall(id: toolId, name: toolName, input: toolInput,
                            userId: msg.userId)

      var invoked = false
      for i in 0 ..< liveClients.len:
        let res: Result[ToolResult, string] =
          try:
            liveClients[i].invoke(call)
          except Exception as e:
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
