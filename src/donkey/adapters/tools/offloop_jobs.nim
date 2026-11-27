## offloop_jobs — the blocking halves of OffLoopIo (app/offloop_io), for the
## blocking executor: each builds its own transport from plain data, so a
## worker thread shares nothing with the loop.

import ../../core/pipeops
import ../../ports/http
import ../../ports/process
import ../http/std_http
import ../process/process_adapter

const OffLoopHttpTimeoutSec* = 30

type
  HttpGetJob* = object
    url*:        string
    headers*:    seq[HttpHeader]
    allowHosts*: seq[string]
    timeoutSec*: int

  HttpPostJob* = object
    patch*: bool          ## PATCH instead of POST
    url*, body*: string
    headers*:    seq[HttpHeader]
    allowHosts*: seq[string]
    timeoutSec*: int

  ProcessJob* = object
    spec*: ProcessSpec

proc httpGetJob*(job: HttpGetJob): Result[HttpResponse, string] {.nimcall, gcsafe, raises: [].} =
  ## Egress only to `allowHosts`; an empty list reaches nothing.
  if job.allowHosts.len == 0:
    return err("no host allowed")
  try:
    newStdHttpAdapter(timeout = max(1, job.timeoutSec), allowlist = job.allowHosts)
      .toRuntimePort().get(job.url, job.headers)
  except CatchableError as e:
    err(e.msg)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err(e.msg)

proc httpPostJob*(job: HttpPostJob): Result[HttpResponse, string] {.nimcall, gcsafe, raises: [].} =
  ## Egress only to `allowHosts`; not retried (the caller decides).
  if job.allowHosts.len == 0:
    return err("no host allowed")
  try:
    let port = newStdHttpAdapter(timeout = max(1, job.timeoutSec), allowlist = job.allowHosts,
                                 retryNonIdempotent = false).toRuntimePort()
    if job.patch: port.patch(job.url, job.body, job.headers)
    else: port.post(job.url, job.body, job.headers)
  except CatchableError as e:
    err(e.msg)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err(e.msg)

proc processJob*(job: ProcessJob): Result[ProcessOutput, string] {.nimcall, gcsafe, raises: [].} =
  try:
    newProcessAdapter().run(job.spec)
  except CatchableError as e:
    err(e.msg)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err(e.msg)
