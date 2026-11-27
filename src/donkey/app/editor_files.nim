## editor_files — reading a file in the person's editor (E10.5).
##
## `editor_read_file` asks through the turn's stream (an `editorRequest`
## carried by an outbound message with the turn's token; the gateway sends
## it as `donkey_editor_request`), and waits for `donkey acp` to answer
## through `POST /v1/acp/editor_result`. Only the person whose turn asked can
## answer, once, before the deadline. Everything runs on the daemon loop:
## the tool's wait and the gateway's answer meet in a Chronos future.

import std/[json, strutils, tables]
import chronos
import ../core/pipeops
import ../core/types
import ../domain/message

const
  MaxEditorFileBytes* = 200 * 1024
  DefaultEditorFileTimeoutMs* = 60_000

type
  PendingRead = object
    userId: UserId
    answer: Future[Result[string, string]].Raising([CancelledError])

  EditorFileRequests* = ref object
    next: int
    pending: Table[string, PendingRead]

proc newEditorFileRequests*(): EditorFileRequests =
  EditorFileRequests()

var gEditorFiles {.threadvar.}: EditorFileRequests
  ## Configured at startup on the daemon loop's thread, where turns and the
  ## gateway both run (as the approval service is).

proc configureEditorFiles*(requests: EditorFileRequests) =
  gEditorFiles = requests

proc currentEditorFiles*(): EditorFileRequests {.gcsafe.} =
  gEditorFiles

func cut(text: string): string =
  if text.len <= MaxEditorFileBytes: return text
  text[0 ..< MaxEditorFileBytes] & "\n\n[… arquivo cortado em " &
    $(MaxEditorFileBytes div 1024) & " KiB; peça um trecho com line e limit]"

proc ask*(r: EditorFileRequests; userId: UserId; outbox: AsyncQueue[OutboundMessage];
          token: uint64; path: string; line = 0; limit = 0;
          timeoutMs = DefaultEditorFileTimeoutMs): Future[Result[string, string]] {.async.} =
  inc r.next
  let id = "ef-" & $r.next
  let answer = Future[Result[string, string]].Raising([CancelledError]).init("editor.read")
  r.pending[id] = PendingRead(userId: userId, answer: answer)
  var params = %* {"path": path}
  if line > 0: params["line"] = %line
  if limit > 0: params["limit"] = %limit
  await outbox.put(OutboundMessage(userId: userId, channel: ckCli, replyKind: rkChannel,
    bridgeToken: token,
    editorRequest: $(%* {"id": id, "method": "fs/read_text_file", "params": params})))
  let answered = await answer.withTimeout(chronos.milliseconds(timeoutMs))
  r.pending.del(id)
  if not answered and answer.completed():
    return answer.read()   ## it landed as the deadline fired
  if not answered:
    return err("the editor did not answer in " & $(timeoutMs div 1000) & " s")
  return answer.read()

proc answer*(r: EditorFileRequests; userId: UserId; id, content, error: string): Result[void, string] =
  ## The editor's answer, from the person the request was for; once.
  let pending = r.pending.getOrDefault(id)
  if pending.answer.isNil or pending.answer.finished:
    return err("no such request, or it already ended")
  if pending.userId != userId:
    return err("no such request, or it already ended")
  if error.len > 0:
    pending.answer.complete(Result[string, string].err("the editor could not read it: " & error))
  else:
    pending.answer.complete(Result[string, string].ok(cut(content)))
  ok()
