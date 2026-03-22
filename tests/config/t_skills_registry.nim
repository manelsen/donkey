import std/[os, strutils, unittest]
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

suite "saveSkillEntry permission guard":

  test "rejects --allow-all at save time":
    let tmp = getTempDir() / "t_skill_dangerous_1.toml"
    defer: (try: removeFile(tmp) except: discard)
    let r = saveSkillEntry(tmp, SkillManifest(
      name: "bad", version: "0.1.0", script: "bad.ts",
      permissions: @["--allow-all"],
    ))
    check r.isErr
    check r.error.contains("not allowed")
    check not fileExists(tmp)

  test "rejects bare --allow-net at save time":
    let tmp = getTempDir() / "t_skill_dangerous_2.toml"
    defer: (try: removeFile(tmp) except: discard)
    let r = saveSkillEntry(tmp, SkillManifest(
      name: "bad", version: "0.1.0", script: "bad.ts",
      permissions: @["--allow-net"],
    ))
    check r.isErr
    check not fileExists(tmp)

  test "rejects wildcard --allow-net=* at save time":
    let tmp = getTempDir() / "t_skill_dangerous_3.toml"
    defer: (try: removeFile(tmp) except: discard)
    let r = saveSkillEntry(tmp, SkillManifest(
      name: "bad", version: "0.1.0", script: "bad.ts",
      permissions: @["--allow-net=*"],
    ))
    check r.isErr
    check not fileExists(tmp)

  test "accepts explicit host permission":
    let tmp = getTempDir() / "t_skill_safe.toml"
    defer: (try: removeFile(tmp) except: discard)
    let r = saveSkillEntry(tmp, SkillManifest(
      name: "ok", version: "0.1.0", script: "ok.ts",
      permissions: @["--allow-net=api.example.com"],
    ))
    check r.isOk
    check fileExists(tmp)

  test "accepts empty permissions":
    let tmp = getTempDir() / "t_skill_noperm.toml"
    defer: (try: removeFile(tmp) except: discard)
    let r = saveSkillEntry(tmp, SkillManifest(
      name: "noperm", version: "0.1.0", script: "noperm.ts",
      permissions: @[],
    ))
    check r.isOk
