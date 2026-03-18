## Pipeline operators — functional composition in the spirit of OCaml/F#.
##
## Usage:
##   "hello" |> strip |> toUpperAscii
##
##   provider.complete(req) >>= extractText >>= saveMemory
##
## |>  — pipe forward:  a |> f   ≡  f(a)          (pure transformations)
## >>= — monadic bind:  r >>= f  ≡  r.andThen(f)  (fallible steps, Result chain)

import std/times
import results
export results

proc nowMs*(): int64 =
  ## Monotonic epoch timestamp in milliseconds. Used for debounce / stream flush timing.
  let t = getTime()
  t.toUnix() * 1_000 + (t.nanosecond div 1_000_000)

template `|>`*[A, B](a: A; f: proc(x: A): B): B =
  f(a)

template `>>=`*[T, E, U](r: Result[T, E];
                          f: proc(x: T): Result[U, E]): Result[U, E] =
  r.andThen(f)
