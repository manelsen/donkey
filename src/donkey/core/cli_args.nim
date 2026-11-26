## cli_args — which long options the binary keeps for itself; the others
## belong to the command (`ctl traces --since 7d`, `ctl mcp login <url>
## --client-id …`) and go back into its arguments, in order.

const BinaryOptions = ["config", "version", "help", "cat", "dev-mode"]

func isBinaryOption*(key: string): bool =
  key in BinaryOptions

func passThroughOption*(key, val: string): seq[string] =
  ## `--key` (and `val` when it came attached, `--key=val`); a value given
  ## as the next word arrives later as an argument of its own.
  result = @["--" & key]
  if val.len > 0: result.add val
