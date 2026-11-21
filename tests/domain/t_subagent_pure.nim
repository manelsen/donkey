## Tests for pure subagent policy and budget logic.

import std/[json, strutils, unittest]
import donkey/domain/subagent_pure

proc runTests*() =
  suite "subagent_pure":

    test "default policy is read-only and includes session_search":
      let tools = defaultSubagentTools()
      check "session_search" in tools
      check "read_file" in tools
      check "fs_read" in tools
      for denied in ["bash", "execute_code", "fs_write", "edit_file",
                     "spawn_subagent", "manage_skills", "task"]:
        check denied notin tools
        check denied notin SubagentReadTools
        check denied in SubagentHardDeniedTools

    test "explicit tool requests cannot escalate":
      check resolveSubagentTools(@["session_search", "fs_read"]).tools ==
            @["session_search", "fs_read"]
      check "bash" in resolveSubagentTools(@["bash"]).denied
      check "execute_code" in resolveSubagentTools(@["execute_code"]).denied
      check "mcp_unknown" in resolveSubagentTools(@["mcp_unknown"]).unknown
      check resolveSubagentTools(@["session_search", "session_search"]).tools ==
            @["session_search"]
      var tooMany: seq[string]
      for i in 0 .. SubagentMaxRequestedTools:
        tooMany.add("session_search")
      check resolveSubagentTools(tooMany).error.len > 0

    test "limits are clamped and zero means default":
      let defaults = defaultSubagentLimits()
      check defaults.maxToolCalls == SubagentDefaultMaxToolCalls
      check defaults.maxTokens == SubagentDefaultMaxTokens

      let clamped = clampSubagentLimits(SubagentLimits(
        maxToolCalls: 1_000,
        maxTokens: 1_000_000,
        maxDurationMs: 99_999_999,
      ))
      check clamped.maxToolCalls == SubagentMaxToolCalls
      check clamped.maxTokens == SubagentMaxTokens
      check clamped.maxDurationMs == SubagentMaxDurationMs

      let zeros = clampSubagentLimits(SubagentLimits())
      check zeros.maxToolCalls == SubagentDefaultMaxToolCalls
      check zeros.maxTokens == SubagentDefaultMaxTokens
      check zeros.maxDurationMs == SubagentDefaultMaxDurationMs

    test "task and depth validation fail closed":
      check spawnDepthError(0).len == 0
      check "depth" in spawnDepthError(1)

      let request = SubagentRequest(task: "summarize this")
      check subagentRequestError(request, 0).len == 0
      check subagentRequestError(SubagentRequest(task: ""), 0).len > 0
      check subagentRequestError(
        SubagentRequest(task: "x", context: repeat("c", SubagentMaxContextChars + 1)),
        0).len > 0

    test "budget decisions cover time, tokens, calls and cancellation":
      let limits = SubagentLimits(maxToolCalls: 2, maxTokens: 10,
                                  maxDurationMs: 1_000)
      let usage = SubagentUsage(startedAtMonoMs: 1_000)
      check checkBudget(usage, limits, 1_500) == bdOk
      usage.recordToolCall(1_500)
      check checkBudget(usage, limits, 1_600) == bdOk
      usage.recordToolCall(1_600)
      check checkBudget(usage, limits, 1_700) == bdToolCallsExceeded

      let tokenUsage = SubagentUsage(startedAtMonoMs: 1_000)
      tokenUsage.recordTokens(5, 5, 1_100)
      check tokenUsage.totalTokens == 10
      check checkBudget(tokenUsage, limits, 1_200) == bdTokensExceeded
      tokenUsage.recordTokens(1, 0, 1_300)
      check tokenUsage.totalTokens == 11
      check checkBudget(tokenUsage, limits, 1_400) == bdTokensExceeded

      let lateUsage = SubagentUsage(startedAtMonoMs: 1_000)
      check checkBudget(lateUsage, limits, 2_000) == bdOk
      check checkBudget(lateUsage, limits, 2_001) == bdTimeExceeded

      let cancelled = SubagentUsage(
        startedAtMonoMs: 1_000, cancelled: true,
        toolCalls: 99, inputTokens: 999, outputTokens: 999)
      check checkBudget(cancelled, limits, 9_999) == bdCancelled

    test "structured results always carry the contract fields":
      let res = SubagentResult(
        subagentId: "sub-1",
        status: ssCompleted,
        text: "done",
        toolCalls: 2,
        inputTokens: 10,
        outputTokens: 3,
        durationMs: 42,
      )
      let j = res.toJson()
      check j["subagent_id"].getStr() == "sub-1"
      check j["status"].getStr() == "completed"
      check j["text"].getStr() == "done"
      check j["tool_calls"].getInt() == 2
      check j["input_tokens"].getInt() == 10
      check j["duration_ms"].getInt() == 42
      check not j.hasKey("cost_usd")

      var priced = res
      priced.hasCost = true
      priced.costUsd = 0.25
      check priced.toJson()["cost_usd"].getFloat() == 0.25

      let spawn = SubagentSpawnResult(subagentId: "sub-2", status: ssRunning)
      check spawn.toJson()["status"].getStr() == "running"

    test "list info reports age and usage":
      let info = SubagentInfo(
        subagentId: "sub-3",
        status: ssRunning,
        createdAtMs: 1_000,
        lastActivityMs: 1_500,
        usage: SubagentUsage(toolCalls: 2, inputTokens: 5, outputTokens: 7),
      )
      let j = info.toJson(2_000)
      check j["age_ms"].getInt() == 1_000
      check j["last_activity_age_ms"].getInt() == 500
      check j["tool_calls"].getInt() == 2
      check j["input_tokens"].getInt() == 5
      check j["output_tokens"].getInt() == 7

when isMainModule:
  runTests()
