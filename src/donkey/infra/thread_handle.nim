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

##
## The argument is copied into the thread, and ORC counts references without
## atomics: a `ref` or a closure environment in it would be counted by two
## threads at once. `spawnThread` refuses such an argument at compile time
## (`sharesNothing`). Strings and seqs are copied, so they are fine; a raw
## `ptr` is an explicit opt-in to manual sharing (locks, atomics); a
## `nimcall` proc has no environment. A thread that needs a closure (an HTTP
## port, a provider) builds it itself, from plain data or a `nimcall` factory.

import std/macros

type ThreadHandle*[T] = ptr Thread[T]

proc gcShared(t: NimNode; seen: var seq[NimNode]): bool {.compileTime.}

proc fieldsShared(n: NimNode; seen: var seq[NimNode]): bool {.compileTime.} =
  ## Walks an object or tuple body: fields, variant branches, the base type.
  case n.kind
  of nnkIdentDefs:
    gcShared(n[^2], seen)
  of nnkOfInherit:
    gcShared(n[0], seen)
  of nnkRecCase:
    if gcShared(n[0][^2], seen): return true
    for i in 1 ..< n.len:
      if fieldsShared(n[i], seen): return true
    false
  of nnkSym:
    n.symKind == nskType and gcShared(n, seen)
  else:
    for c in n:
      if fieldsShared(c, seen): return true
    false

proc bodyShared(t, impl: NimNode; seen: var seq[NimNode]): bool {.compileTime.} =
  ## An object or tuple `t` with its expanded body `impl`. Only these are
  ## recorded in `seen`: they are the only types that can contain themselves.
  ## Compared by type identity, not by name (two scopes may each have a
  ## `Payload`), and recorded under the type itself, so `Box[int]` and
  ## `Box[ref int]` stay distinct.
  for known in seen:
    if sameType(known, t): return false  ## recursive, or met before
  seen.add t
  if impl.kind == nnkTupleConstr:
    for c in impl:
      if gcShared(c, seen): return true
    false
  else:
    fieldsShared(impl, seen)

proc gcShared(t: NimNode; seen: var seq[NimNode]): bool =
  ## True when a value of type `t` can hold a ref or a closure environment.
  case t.typeKind
  of ntyRef:
    true
  of ntyPtr, ntyPointer, ntyCString, ntyString, ntyBool, ntyChar, ntyEnum,
     ntyInt..ntyUInt64, ntyNil, ntyEmpty, ntyVoid:
    false
  of ntyProc:
    ## A proc type is a closure unless declared with another convention.
    let impl = t.getTypeImpl
    var callConvSet = false
    if impl.kind == nnkProcTy and impl.len > 1:
      for p in impl[1]:
        if p.kind in {nnkIdent, nnkSym} and
           $p in ["nimcall", "cdecl", "stdcall", "noconv", "inline", "fastcall",
                  "safecall", "syscall"]:
          callConvSet = true
    not callConvSet
  of ntyDistinct, ntyGenericInst, ntyAlias, ntyTypeDesc:
    ## A wrapper is judged by what it expands to; an object body is examined
    ## right here, under the instance's own identity.
    let impl = t.getTypeImpl
    if impl == t: return false
    if impl.kind == nnkDistinctTy: gcShared(impl[0], seen)
    elif impl.kind in {nnkObjectTy, nnkTupleConstr, nnkTupleTy}:
      bodyShared(t, impl, seen)
    else: gcShared(impl, seen)
  of ntySequence, ntyOpenArray, ntyVarargs, ntySet, ntyRange, ntyUncheckedArray:
    gcShared(t.getTypeImpl[^1], seen)
  of ntyArray:
    gcShared(t.getTypeImpl[2], seen)
  of ntyTuple, ntyObject:
    bodyShared(t, t.getTypeImpl, seen)
  else:
    true  ## unknown kind: refuse rather than guess

macro sharesNothing*(T: typedesc): bool =
  ## True when a `T` holds no ref and no closure: safe to copy into another
  ## thread under ORC.
  var seen: seq[NimNode]
  newLit(not gcShared(T.getTypeInst[1], seen))

proc spawnThread*[T](fn: proc(arg: T) {.thread, nimcall.};
                     arg: T): ThreadHandle[T] =
  ## Starts `fn(arg)` on a new thread. Raises ResourceExhaustedError like
  ## `createThread` when the OS refuses.
  when not sharesNothing(T):
    {.error: "spawnThread: the thread argument holds a ref or a closure, " &
             "which ORC would count from two threads; pass plain data and " &
             "build it in the thread".}
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
