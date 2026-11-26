## web_tool_jobs — the worker half of the web tools (app/tools/web_tools'
## WebToolJob): it builds the same transport the session uses (the web
## allowlist, DONKEY_WEB_PROXY) from plain data and runs the job, on a
## blocking-executor thread. Top level: it joins an app operation to an
## adapter, which neither layer may do by itself.

import donkey/core/pipeops
import donkey/adapters/http/std_http
import donkey/app/tools/web_tools

proc webToolWorker*(job: WebToolJob): Result[WebToolOutput, string] {.nimcall, gcsafe, raises: [].} =
  try:
    let http = newStdHttpAdapter(allowlist = job.transportAllowlist, proxy = job.proxy).toRuntimePort()
    ok(runWebToolJob(job, http))
  except CatchableError as e:
    err(e.msg)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err(e.msg)
