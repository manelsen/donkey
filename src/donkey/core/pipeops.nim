## Pipeline operators — functional composition in the spirit of OCaml/F#.
##
## Usage:
##   "hello" |> strip |> toUpperAscii
##
##   provider.complete(req) >>= extractText >>= saveMemory
##
## |>  — pipe forward:  a |> f   ≡  f(a)          (pure transformations)
## >>= — monadic bind:  r >>= f  ≡  r.andThen(f)  (fallible steps, Result chain)

import results
export results

template `|>`*[A, B](a: A; f: proc(x: A): B): B =
  f(a)

template `>>=`*[T, E, U](r: Result[T, E];
                          f: proc(x: T): Result[U, E]): Result[U, E] =
  r.andThen(f)
