## spawnThread keeps the thread in shared memory behind a pointer, so a
## global handle is gcsafe: the starter below is {.gcsafe.} and touches the
## global with no cast.

import std/[atomics, json, unittest]
import donkey/infra/thread_handle

type Args = object
  label: string
  times: int

var gHandle: ThreadHandle[Args]
var gSeen: Atomic[int]

proc worker(args: Args) {.thread.} =
  for _ in 0 ..< args.times:
    discard gSeen.fetchAdd(args.label.len)

proc start() {.gcsafe.} =
  gHandle = spawnThread(worker, Args(label: "abc", times: 4))

type
  Plain = object
    name: string
    tags: seq[string]
    count: int
    pair: (string, int)
    fixed: array[2, string]
  WithRef = object
    name: string
    node: JsonNode
  WithClosure = object
    fn: proc(x: int): int {.gcsafe.}
  WithNimcall = object
    fn: proc(x: int): int {.nimcall, gcsafe.}
  WithPtr = object
    shared: ptr int
  Nested = object
    inner: seq[WithRef]
  Variant = object
    case hasRef: bool
    of true: node: JsonNode
    of false: text: string
  Leaf = ref object
    value: int
  Payload = object
    ## Plain; homonymChecks declares a `Payload` holding a ref.
    value: int
  Tree = object
    children: seq[Tree]

proc homonymChecks(): array[4, bool] =
  ## Two types named `Payload`: this local one holds a ref, the module's one
  ## does not. Checked in both field orders.
  type
    Payload = object
      value: ref int
    PlainFirst = object
      first: t_thread_handle.Payload
      second: Payload
    RefFirst = object
      first: Payload
      second: t_thread_handle.Payload
  [sharesNothing(t_thread_handle.Payload), sharesNothing(Payload),
   sharesNothing(PlainFirst), sharesNothing(RefFirst)]

proc runTests*() =
  suite "thread arguments share nothing the GC counts":
    test "plain values, nimcall procs and raw pointers are accepted":
      check sharesNothing(Plain)
      check sharesNothing(WithNimcall)
      check sharesNothing(WithPtr)
      check sharesNothing(string)
      check sharesNothing(int)

    test "a ref or a closure anywhere inside is refused":
      check not sharesNothing(WithRef)
      check not sharesNothing(WithClosure)
      check not sharesNothing(Nested)
      check not sharesNothing(Variant)
      check not sharesNothing(Leaf)
      check not sharesNothing(JsonNode)

    test "two types with the same name are told apart, in either order":
      let shares = homonymChecks()
      check shares[0]          ## the module's plain Payload
      check not shares[1]      ## the local Payload with a ref
      check not shares[2]      ## plain first, ref second
      check not shares[3]      ## ref first, plain second

    test "a recursive plain type is accepted":
      check sharesNothing(Tree)

    test "spawnThread does not compile with such an argument":
      proc takesRef(arg: WithRef) {.thread.} = discard
      check not compiles(spawnThread(takesRef, WithRef()))

  suite "thread handle":
    test "a thread started from gcsafe code runs with its argument and is joined":
      gSeen.store(0)
      start()
      check gHandle != nil
      joinAndFree(gHandle)
      check gHandle == nil
      check gSeen.load == 12

when isMainModule:
  runTests()
