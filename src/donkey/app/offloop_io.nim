## offloop_io — I/O a native tool may await without holding the event loop
## (second round, front 2).
##
## The daemon installs, at startup and on the loop, an HTTP GET and a process
## run that it carries out on the blocking executor (adapters/tools/
## offloop_jobs). Native tools run on the loop, so the installed value is
## thread-local to it, like the provider credentials; another thread, or a
## daemon that installed nothing, gets empty fields, and the tool refuses
## instead of blocking.

import chronos
import ../core/pipeops
import ../infra/thread_owner
import ../ports/http
import ../ports/process

type
  AsyncHttpGet* = proc(url: string; headers: seq[HttpHeader]; allowHosts: seq[string]):
      Future[Result[HttpResponse, string]] {.async: (raises: []), gcsafe.}
    ## A GET that may only reach `allowHosts`.
  AsyncHttpPost* = proc(url, body: string; headers: seq[HttpHeader]; allowHosts: seq[string]):
      Future[Result[HttpResponse, string]] {.async: (raises: []), gcsafe.}
    ## A POST that may only reach `allowHosts`.
  AsyncProcessRun* = proc(spec: ProcessSpec): Future[Result[ProcessOutput, string]]
      {.async: (raises: []), gcsafe.}

  OffLoopIo* = object
    httpGet*:    AsyncHttpGet
    httpPost*:   AsyncHttpPost
    processRun*: AsyncProcessRun

var
  gIo {.threadvar.}: OffLoopIo
  gIoOwner: ThreadOwner

proc useOffLoopIo*(io: OffLoopIo) {.gcsafe, raises: [].} =
  if gIoOwner.isOwner("off-loop io"):
    gIo = io

proc offLoopIo*(): OffLoopIo {.gcsafe, raises: [].} =
  if gIoOwner.isOwner("off-loop io"): gIo else: OffLoopIo()
