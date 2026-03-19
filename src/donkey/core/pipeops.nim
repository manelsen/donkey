## Pipeline operators — functional composition in the spirit of OCaml/F#.
##
## Usage:
##   "hello" |> strip |> toUpperAscii
##
##   provider.complete(req) >>= extractText >>= saveMemory
##
## |>  — pipe forward:  a |> f   ≡  f(a)          (pure transformations)
## >>= — monadic bind:  r >>= f  ≡  r.andThen(f)  (fallible steps, Result chain)

import std/monotimes
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

func splitChunks*(text: string; maxLen: int): seq[string] =
  ## Splits text into chunks of at most maxLen characters.
  ## Prefers splitting at newlines or spaces; falls back to hard cut.
  if text.len <= maxLen:
    return @[text]
  var pos = 0
  while pos < text.len:
    let remaining = text.len - pos
    if remaining <= maxLen:
      result.add(text[pos .. ^1])
      break
    var found = -1
    for i in countdown(pos + maxLen - 1, pos + maxLen div 2):
      if text[i] == '\n': found = i + 1; break
    if found < 0:
      for i in countdown(pos + maxLen - 1, pos + maxLen div 2):
        if text[i] == ' ': found = i + 1; break
    if found < 0: found = pos + maxLen
    result.add(text[pos ..< found])
    pos = found
