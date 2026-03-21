import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/config/skills_registry

suite "skills registry permission policy":

  test "parseAllowNetHosts extracts explicit hosts":
    check parseAllowNetHosts("--allow-net=api.github.com,docs.nim-lang.org") ==
      @["api.github.com", "docs.nim-lang.org"]

  test "rejects unrestricted allow-all":
    let result = validateSkillPermissions(@["-A"], @[])
    check result.isErr
    check result.error.contains("not allowed")

  test "rejects bare allow-net":
    let result = validateSkillPermissions(@["--allow-net"], @[])
    check result.isErr
    check result.error.contains("explicit hosts")

  test "rejects skill host outside configured allowlist":
    let result = validateSkillPermissions(
      @["--allow-net=example.com"],
      @["api.github.com"],
    )
    check result.isErr
    check result.error.contains("outside the configured web allowlist")

  test "accepts allow-net hosts inside configured allowlist":
    let result = validateSkillPermissions(
      @["--allow-net=docs.nim-lang.org"],
      @["nim-lang.org"],
    )
    check result.isOk
    check result.value == @["--allow-net=docs.nim-lang.org"]
