## `editor_read_file` (E10.5): the model reads a file in the person's editor,
## only in an editor's turn, after approval; elsewhere it says why.

import std/[json, strutils, unittest]
import chronos
import donkey/adapters/filesystem/fs_adapter
import donkey/app/native_tools
import donkey/app/session_state
import donkey/app/editor_files
import donkey/app/approval_runtime
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message

proc call(ctx: NativeCtx; input: string): Future[NativeToolResult] =
  executeNativeTool(ToolCallRequest(id: "1", name: "editor_read_file", inputJson: input),
                    ctx, newSessionState(), @[])

proc answerLater(r: EditorFileRequests; outbox: AsyncQueue[OutboundMessage];
                 content: string) {.async.} =
  let asked = await outbox.get()
  let id = parseJson(asked.editorRequest)["id"].getStr
  discard r.answer(asked.userId, id, content, "")

proc runTests*() =
  suite "editor_read_file":
    test "outside an editor's turn it says so, asking nothing":
      let outbox = newAsyncQueue[OutboundMessage](4)
      let ctx = NativeCtx(uid: UserId("ana"), channel: ckTelegram, fs: newFsAdapter(),
                          outbox: outbox, editorFiles: newEditorFileRequests())
      let r = waitFor ctx.call("""{"path":"src/a.nim"}""")
      check r.handled and "editor" in r.text.toLowerAscii and outbox.len == 0

    test "in an editor's turn it asks the editor and returns the content":
      let outbox = newAsyncQueue[OutboundMessage](4)
      let files = newEditorFileRequests()
      let ctx = NativeCtx(uid: UserId("ana"), channel: ckCli, fs: newFsAdapter(),
                          outbox: outbox, editorFiles: files, bridgeToken: 9)
      let reading = ctx.call("""{"path":"src/a.nim","line":3,"limit":20}""")
      waitFor files.answerLater(outbox, "proc main() = discard")
      let r = waitFor reading
      check r.handled and "proc main() = discard" in r.text

    test "a path is required":
      let ctx = NativeCtx(uid: UserId("ana"), channel: ckCli, fs: newFsAdapter(),
                          outbox: newAsyncQueue[OutboundMessage](4),
                          editorFiles: newEditorFileRequests(), bridgeToken: 9)
      check "path" in (waitFor ctx.call("{}")).text

    test "it asks for approval by default":
      check "editor_read_file" in defaultApprovalTools()

when isMainModule:
  runTests()
