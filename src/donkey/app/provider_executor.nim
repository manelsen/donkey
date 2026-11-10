## Provider executor — runs blocking provider calls on a worker thread.
##
## The worker receives only plain data (ProviderSpec + CompletionRequest) and a
## gcsafe builder proc; it does NOT share the session closure or routing state.
## Selection and routing hooks stay on the Chronos event loop.

import chronos
import ../core/pipeops
import ../ports/provider
import ../domain/message

type
  AsyncCompleteFn* = proc(req: CompletionRequest):
      Future[Result[CompletionResponse, string]] {.gcsafe.}

  ProviderJob = object
    builder: ProviderRuntimeBuilder
    spec:    ProviderSpec
    req:     CompletionRequest
    ch:      ptr Channel[Result[CompletionResponse, string]]

proc callProvider(job: ProviderJob): Result[CompletionResponse, string] {.gcsafe, raises: [].} =
  try:
    let bundle = job.builder(job.spec)
    if bundle.completeFn == nil:
      return err("provider unavailable: " & job.spec.providerName)
    bundle.completeFn(job.req)
  except Exception as e:
    err(e.msg)

proc doProviderJob(job: ProviderJob) {.thread, gcsafe.} =
  job.ch[].send(callProvider(job))

proc asyncProviderComplete*(builder: ProviderRuntimeBuilder;
                            spec: ProviderSpec;
                            req: CompletionRequest
                           ): Future[Result[CompletionResponse, string]] {.async.} =
  ## Runs one provider call off the event loop. On cancellation the finally
  ## waits for the worker, so the channel cannot be freed under the thread.
  var ch: Channel[Result[CompletionResponse, string]]
  ch.open(1)
  var t: Thread[ProviderJob]
  createThread(t, doProviderJob, ProviderJob(builder: builder, spec: spec, req: req, ch: addr ch))
  try:
    while true:
      let (hasResult, res) = ch.tryRecv()
      if hasResult:
        return res
      await sleepAsync(milliseconds(10))
  finally:
    joinThread(t)
    ch.close()
