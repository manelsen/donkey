## a2a_server — the A2A methods the daemon answers (E13.4).
##
## The gateway authenticates the bearer token (a paired remote agent) and
## hands the person it was paired with; here each method is answered.
## `SendMessage` runs one turn as that person and waits for it (the
## protocol's default, blocking), so the task comes back finished; the
## newest tasks are kept for `GetTask`, each visible only to its person.

import std/[deques, json, tables]
import chronos
import ../core/pipeops
import ../core/types
import ../domain/a2a/a2a_pure

const MaxA2aTasks* = 256

type
  A2aTurnFn* = proc(person: UserId; text: string): Future[Result[string, string]]
                   {.gcsafe, raises: [].}
  A2aIdFn* = proc(): string {.gcsafe, raises: [].}
  A2aClockFn* = proc(): string {.gcsafe, raises: [].}

  StoredTask = object
    owner: UserId
    task: A2aTask

  A2aServer* = ref object
    turn: A2aTurnFn
    newId: A2aIdFn
    now: A2aClockFn
    tasks: Table[string, StoredTask]
    order: Deque[string]

proc newA2aServer*(turn: A2aTurnFn; newId: A2aIdFn; now: A2aClockFn): A2aServer =
  A2aServer(turn: turn, newId: newId, now: now)

func taskCount*(s: A2aServer): int = s.tasks.len

proc keep(s: A2aServer; owner: UserId; t: A2aTask) =
  if not s.tasks.hasKey(t.id):
    s.order.addLast t.id
  s.tasks[t.id] = StoredTask(owner: owner, task: t)
  while s.order.len > MaxA2aTasks:
    s.tasks.del s.order.popFirst()

proc find(s: A2aServer; person: UserId; params: JsonNode): Result[A2aTask, RpcError] =
  let id = params{"id"}.getStr
  let stored = s.tasks.getOrDefault(id)
  if id.len == 0 or stored.task.id.len == 0 or stored.owner != person:
    return err(RpcError(code: ErrTaskNotFound, message: "Task not found"))
  ok(stored.task)

proc sendMessage(s: A2aServer; person: UserId; call: RpcCall): Future[JsonNode] {.async.} =
  let msg = incomingMessage(call.params)
  if msg.isErr:
    return rpcError(call.id, RpcError(code: ErrInvalidParams, message: msg.error))
  var task = A2aTask(id: s.newId(),
                     contextId: (if msg.get.contextId.len > 0: msg.get.contextId else: s.newId()))
  let reply = await s.turn(person, msg.get.text)
  if reply.isOk:
    task.state = tsCompleted
    task.reply = reply.get
  else:
    task.state = tsFailed
    task.reply = reply.error
  task.timestamp = s.now()
  s.keep(person, task)
  return rpcResult(call.id, %*{"task": taskJson(task)})

proc handleRpc*(s: A2aServer; person: UserId; body: string): Future[JsonNode] {.async.} =
  let call = parseRpc(body)
  if call.isErr:
    return rpcError(newJNull(), call.error)
  let c = call.get
  case c.meth
  of "SendMessage":
    return await s.sendMessage(person, c)
  of "GetTask":
    let t = s.find(person, c.params)
    if t.isErr: return rpcError(c.id, t.error)
    return rpcResult(c.id, taskJson(t.get))
  of "CancelTask":
    let t = s.find(person, c.params)
    if t.isErr: return rpcError(c.id, t.error)
    ## Turns are answered before SendMessage returns: nothing left to cancel.
    return rpcError(c.id, RpcError(code: ErrTaskNotCancelable, message: "Task cannot be canceled"))
  else:
    return rpcError(c.id, RpcError(code: ErrMethodNotFound, message: "Method not found"))

proc replyText*(status: int; body: string): Result[string, string] =
  ## The answer of a turn run through the agent endpoint: the completion's
  ## text on 200, the error's message otherwise.
  let node =
    try: parseJson(body)
    except CatchableError: return err("the turn's reply is not JSON (status " & $status & ")")
  if status == 200:
    let choices = node{"choices"}
    if choices.isNil or choices.kind != JArray or choices.len == 0:
      return err("the turn ended without an answer")
    return ok(choices[0]{"message"}{"content"}.getStr)
  let message = node{"error"}{"message"}.getStr
  err(if message.len > 0: message else: "the turn failed (status " & $status & ")")
