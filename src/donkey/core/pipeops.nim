## Pipeline operators — functional composition in the spirit of OCaml/F#.
##
## Usage:
##   "hello" |> strip |> toUpperAscii
##
##   provider.complete(req) >>= extractText >>= saveMemory
##
## |>  — pipe forward:  a |> f   ≡  f(a)          (pure transformations)
## >>= — monadic bind:  r >>= f  ≡  r.andThen(f)  (fallible steps, Result chain)

import std/[times, monotimes]
import results
export results

template `|>`*(a: untyped; f: untyped): untyped =
  f(a)

template `>>=`*[T, E, U](r: Result[T, E];
                          f: proc(x: T): Result[U, E]): Result[U, E] =
  r.andThen(f)

proc nowMs*(): int64 =
  ## Returns current monotonic time in milliseconds.
  let t = getMonoTime()
  (t.ticks div 1_000_000).int64
