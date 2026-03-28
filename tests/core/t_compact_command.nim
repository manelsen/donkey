import std/unittest
import donkey/domain/message
import donkey/domain/agent_message
import donkey/core/commands/command_routing

suite "compact command":

  test "parseCommandText parses /compact":
    let cmd = parseCommandText("/compact")
    check cmd.kind == cmdCompact
    check cmd.route == crSessionTask
    check cmd.value == ""

  test "isSessionTaskCommand returns true for cmdCompact":
    check isSessionTaskCommand(cmdCompact) == true

  test "commandTaskKind returns tkCompact for cmdCompact":
    let decision = CommandDecision(kind: cmdCompact, route: crSessionTask, value: "")
    check commandTaskKind(decision) == tkCompact
