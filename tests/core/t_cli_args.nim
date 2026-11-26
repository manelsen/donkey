## The binary's own options (--config, --version, …) are taken; any other
## long option belongs to the command and goes back into its arguments, in
## order: `ctl traces --since 7d`, `ctl mcp login <url> --client-id x` used to
## lose them.

import std/unittest
import donkey/core/cli_args

proc runTests*() =
  suite "cli args":

    test "an unknown long option goes back as --name, then its value if attached":
      check passThroughOption("since", "") == @["--since"]
      check passThroughOption("since", "7d") == @["--since", "7d"]
      check passThroughOption("client-id", "abc") == @["--client-id", "abc"]

    test "the binary's own options are not passed through":
      for own in ["config", "version", "help", "cat", "dev-mode"]:
        check isBinaryOption(own)
      check not isBinaryOption("since")

when isMainModule:
  runTests()
