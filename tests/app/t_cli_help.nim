## The CLI's version line and help text.

import std/[strutils, unittest]
import donkey/core/app_meta
import donkey/app/cli_help

proc runTests*() =
  suite "cli help":
    test "the version line names the binary and its version":
      check versionText() == AppSlug & " " & AppVersion

    test "the help starts with the version and lists options and commands":
      let help = cliHelpText()
      check help.startsWith(versionText())
      check "Usage:\n  " & AppSlug & " [options] [command]" in help
      check "--config <path>" in help
      check ConfigFileName in help
      for command in ["setup", "start", "ctl status", "ctl user list",
                      "ctl memory import <uuid>", "service install", "doctor"]:
        check command in help

when isMainModule:
  runTests()
