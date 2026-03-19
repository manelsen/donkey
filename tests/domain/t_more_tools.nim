import unittest
import std/json
import donkey/domain/more_tools

suite "tool metadata — non-empty":
  test "bash": check BashToolName.len > 0 and BashToolDescription.len > 0
  test "hashline": check HashlineToolName.len > 0 and HashlineToolDescription.len > 0
  test "find": check FindToolName.len > 0 and FindToolDescription.len > 0
  test "grep": check GrepToolName.len > 0 and GrepToolDescription.len > 0
  test "fetch": check FetchToolName.len > 0 and FetchToolDescription.len > 0
  test "web_search": check WebSearchToolName.len > 0 and WebSearchToolDescription.len > 0
  test "calc": check CalcToolName.len > 0 and CalcToolDescription.len > 0
  test "render_mermaid": check RenderMermaidToolName.len > 0 and RenderMermaidToolDescription.len > 0
  test "inspect_image": check InspectImageToolName.len > 0 and InspectImageToolDescription.len > 0
  test "ask": check AskToolName.len > 0 and AskToolDescription.len > 0
  test "todo_write": check TodoWriteToolName.len > 0 and TodoWriteToolDescription.len > 0
  test "checkpoint": check CheckpointToolName.len > 0 and CheckpointToolDescription.len > 0
  test "rewind": check RewindToolName.len > 0 and RewindToolDescription.len > 0
  test "task": check TaskToolName.len > 0 and TaskToolDescription.len > 0
  test "submit_result": check SubmitResultToolName.len > 0 and SubmitResultToolDescription.len > 0
  test "report_finding": check ReportFindingToolName.len > 0 and ReportFindingToolDescription.len > 0
  test "cancel_job": check CancelJobToolName.len > 0 and CancelJobToolDescription.len > 0
  test "await": check AwaitToolName.len > 0 and AwaitToolDescription.len > 0

suite "tool schemas — valid JSON with type=object":
  proc checkSchema(schema: string) =
    let j = parseJson(schema)
    check j["type"].getStr() == "object"

  test "bash":         checkSchema(BashToolSchema)
  test "hashline":     checkSchema(HashlineToolSchema)
  test "find":         checkSchema(FindToolSchema)
  test "grep":         checkSchema(GrepToolSchema)
  test "fetch":        checkSchema(FetchToolSchema)
  test "web_search":   checkSchema(WebSearchToolSchema)
  test "calc":         checkSchema(CalcToolSchema)
  test "render_mermaid": checkSchema(RenderMermaidToolSchema)
  test "inspect_image":  checkSchema(InspectImageToolSchema)
  test "ask":          checkSchema(AskToolSchema)
  test "todo_write":   checkSchema(TodoWriteToolSchema)
  test "checkpoint":   checkSchema(CheckpointToolSchema)
  test "rewind":       checkSchema(RewindToolSchema)
  test "task":         checkSchema(TaskToolSchema)
  test "submit_result": checkSchema(SubmitResultToolSchema)
  test "report_finding": checkSchema(ReportFindingToolSchema)
  test "cancel_job":   checkSchema(CancelJobToolSchema)
  test "await":        checkSchema(AwaitToolSchema)

suite "required fields present in schemas":
  test "bash requires command":
    let j = parseJson(BashToolSchema)
    check j["required"][0].getStr() == "command"

  test "grep requires pattern and path":
    let j = parseJson(GrepToolSchema)
    let req = j["required"]
    check req[0].getStr() == "pattern"
    check req[1].getStr() == "path"

  test "find requires path":
    let j = parseJson(FindToolSchema)
    check j["required"][0].getStr() == "path"

  test "calc requires expression":
    let j = parseJson(CalcToolSchema)
    check j["required"][0].getStr() == "expression"
