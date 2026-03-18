## DenoSkillAdapter unit tests — verifies constructor only (no subprocess).

import std/[strutils, unittest]
import donkey/adapters/tool/deno_skill

suite "DenoSkillAdapter constructor":

  test "command is 'deno'":
    let a = newDenoSkillAdapter("/path/to/skill.ts", @["--allow-net"])
    check a.command == "deno"

  test "args start with 'run'":
    let a = newDenoSkillAdapter("/path/to/skill.ts", @["--allow-net"])
    check a.args[0] == "run"

  test "script path is in args":
    let a = newDenoSkillAdapter("/skills/search.ts", @["--allow-net"])
    check a.args[^1].contains("search.ts")

  test "permissions are in args":
    let a = newDenoSkillAdapter("/s.ts", @["--allow-net", "--allow-read"])
    check a.args.contains("--allow-net")
    check a.args.contains("--allow-read")

  test "empty permissions still builds valid args":
    let a = newDenoSkillAdapter("/s.ts", @[])
    check a.command == "deno"
    check a.args.len >= 2  ## at least "run" + script
