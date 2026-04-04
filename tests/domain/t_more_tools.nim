import unittest
import std/json
import std/strutils
import donkey/domain/more_tools

suite "tool metadata — non-empty":
  test "bash": check BashToolName.len > 0 and BashToolDescription.len > 0
  test "read_file": check ReadFileToolName.len > 0 and ReadFileToolDescription.len > 0
  test "edit_file": check EditFileToolName.len > 0 and EditFileToolDescription.len > 0
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
  test "manage_skills": check ManageSkillsToolName.len > 0 and ManageSkillsToolDescription.len > 0
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
  test "read_file":    checkSchema(ReadFileToolSchema)
  test "edit_file":    checkSchema(EditFileToolSchema)
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
  test "manage_skills": checkSchema(ManageSkillsToolSchema)
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

  test "read_file requires path":
    let j = parseJson(ReadFileToolSchema)
    check j["required"][0].getStr() == "path"

  test "edit_file requires path and edits":
    let j = parseJson(EditFileToolSchema)
    let req = j["required"]
    check req[0].getStr() == "path"
    check req[1].getStr() == "edits"

  test "calc requires expression":
    let j = parseJson(CalcToolSchema)
    check j["required"][0].getStr() == "expression"

suite "tool metadata matches runtime contracts":

  test "bash description reflects paddock execution":
    check BashToolDescription.contains("paddock")

  test "grep schema declares literal search":
    let j = parseJson(GrepToolSchema)
    check j["properties"]["pattern"]["description"].getStr().contains("Literal")

  test "task and await descriptions mention job ids":
    check TaskToolDescription.contains("job_id")
    check AwaitToolDescription.contains("job_id")

  test "ask description mentions interruption on rebuild":
    check AskToolDescription.contains("interruption")

  test "manage_skills description covers installation guidance and next message activation":
    check ManageSkillsToolDescription.contains("how to install or enable a skill")
    check ManageSkillsToolDescription.contains("next message")

  test "inspect_image description mentions default describe behavior":
    check InspectImageToolDescription.contains("detailed description")
