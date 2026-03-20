import std/[strutils, unittest]
import donkey/core/pipeops

proc prefix(prefixText, value: string): string =
  prefixText & value

suite "pipeops":

  test "`|>` pipes into first argument":
    check (" donkey " |> strip |> toUpperAscii) == "DONKEY"

  test "`|>->` pipes into last argument of a call":
    check ("world" |>-> prefix("hello ")) == "hello world"

  test "`|>->` calls unary functions directly":
    check (" donkey " |>-> strip) == "donkey"
