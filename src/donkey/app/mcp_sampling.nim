## mcp_sampling — an MCP server's sampling request, in the daemon
## (PRD-roadmap E5.1-E5.3).
##
## The request arrives in the middle of a person's tool call (the MCP client
## hands over that call). The person is asked on their channel: once, always
## for this server (an approval that stands, keyed by what runs, not by its
## name), or deny. Approved, the request runs through the person's own model
## route, without tools, its token limit capped, and within a daily token cap
## per server; a request past the cap is refused without asking. Outside a
## person's call (the startup listing) there is nobody to ask: refused.

import std/[json, strutils]
import chronos
import chronos/asyncsync
import ../core/log
import ../core/pipeops
import ../core/security/approval
import ../core/types
import ../domain/message
import ../domain/tools/mcp_sampling_pure
import ../ports/runtime_state
import ../ports/tool
import ./approval_runtime
import ./metrics
import ./provider_executor

type
  SamplingDeps* = object
    outbox*:        AsyncQueue[OutboundMessage]
    completeFor*:   proc(userId: UserId): AsyncCompleteFn {.gcsafe.}
      ## The person's model route.
    budget*:        ref SamplingBudget
    dailyTokenCap*: int
    maxTokensCap*:  int
    log*:           Logger

  SamplingHandler* = proc(meth: string; params: JsonNode; call: ToolCall):
      Future[Result[JsonNode, string]] {.async: (raises: []), gcsafe.}

const SamplingMethod* = "sampling/createMessage"

proc samplingHandler*(serverName, identity: string; deps: SamplingDeps): SamplingHandler =
  let key = samplingApprovalKey(identity)
  result = proc(meth: string; params: JsonNode; call: ToolCall):
      Future[Result[JsonNode, string]] {.async: (raises: []), gcsafe.} =
    if meth != SamplingMethod:
      return err("Method not found: " & meth)
    if call.userId.len == 0:
      return err("sampling is only possible during a person's tool call")
    let req = parseSamplingRequest(params).valueOr:
      return err(error)
    var channel = ckTelegram
    if not parseChannelKindName(call.channel, channel):
      return err("no channel to ask the person on")
    let started = epochMs()
    deps.budget.dailyCap = deps.dailyTokenCap
    ## What may be spent is the limit after capping; it is reserved now, so
    ## requests in flight hold their share and the cap holds, and settled
    ## (or given back) at the end.
    let reserved = min(req.maxTokens, deps.maxTokensCap)
    if not deps.budget[].allows(identity, reserved, started):
      deps.log.warn("mcp sampling: " & serverName & " is past its daily token cap")
      return err("the server's daily sampling budget is spent")
    deps.budget[].spend(identity, reserved, started)
    template giveBack() =
      deps.budget[].spend(identity, -reserved, started)
    let decision =
      try:
        await requestStandingApproval(currentApprovalService(), UserId(call.userId),
          channel, deps.outbox, key, "sampling de " & serverName,
          approvalSummary(serverName, req), deps.log)
      except CancelledError:
        giveBack()
        return err("sampling cancelled")
      except CatchableError as e:
        giveBack()
        return err("sampling approval failed: " & e.msg)
    if decision != adApproved:
      giveBack()
      recordToolCall("sampling:" & serverName, float(epochMs() - started), ok = false)
      return err("the person declined the sampling request")
    let complete =
      try: deps.completeFor(UserId(call.userId))
      except Exception as e:  ## effect boundary: callee raises are unannotated
        giveBack()
        recordToolCall("sampling:" & serverName, float(epochMs() - started), ok = false)
        return err("no model route: " & e.msg)
    let completion =
      try:
        await safeAsyncComplete(complete, toCompletionRequest(req, deps.maxTokensCap))
      except CancelledError:
        giveBack()
        return err("sampling cancelled")
      except CatchableError as e:
        giveBack()
        return err("sampling failed: " & e.msg)
    if completion.isErr:
      giveBack()
      recordToolCall("sampling:" & serverName, float(epochMs() - started), ok = false)
      return err("the model failed: " & completion.error)
    let resp = completion.get
    ## A provider that reports no usage is charged what was reserved.
    let used = resp.inputTokens + resp.outputTokens
    deps.budget[].spend(identity, (if used > 0: used else: reserved) - reserved, started)
    recordToolCall("sampling:" & serverName, float(epochMs() - started), ok = true)
    deps.log.info("mcp sampling: " & serverName & " for " & call.userId & " (" &
                  $(resp.inputTokens + resp.outputTokens) & " tokens)")
    return ok(samplingResult(resp.text, ""))
