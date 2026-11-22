## Long-lived background threads (gateways, webhook servers) started from
## gcsafe code.
##
## `createThread` needs a `Thread[T]` that outlives the thread, and adapters
## kept one in a global. A `Thread[T]` carries its argument (strings, a
## logger) inside, so that global held GC memory and every start needed a
## `{.cast(gcsafe).}`. `spawnThread` allocates the `Thread[T]` in shared
## memory and hands back a pointer: a global pointer holds nothing the GC
## owns. The block lives as long as the process (the thread may outlive the
## caller), unless `joinAndFree` releases it after the thread ended.

type ThreadHandle*[T] = ptr Thread[T]

proc spawnThread*[T](fn: proc(arg: T) {.thread, nimcall.};
                     arg: T): ThreadHandle[T] =
  ## Starts `fn(arg)` on a new thread. Raises ResourceExhaustedError like
  ## `createThread` when the OS refuses.
  result = cast[ThreadHandle[T]](allocShared0(sizeof(Thread[T])))
  try:
    createThread(result[], fn, arg)
  except CatchableError as e:
    reset(result[])  ## destroy the argument createThread may have stored
    deallocShared(result)
    raise e

proc running*[T](handle: ThreadHandle[T]): bool =
  handle != nil and handle[].running

proc joinAndFree*[T](handle: var ThreadHandle[T]) =
  ## Waits for the thread and releases its block.
  if handle == nil: return
  joinThread(handle[])
  reset(handle[])  ## destroy the stored argument (strings, closures) first
  deallocShared(handle)
  handle = nil
