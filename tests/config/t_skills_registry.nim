## SkillsRegistry unit tests — SkillManifest, load, save, per-user override.

import std/[os, sequtils, unittest]
import donkey/config/skills_registry

suite "loadSkillRegistry":

  test "missing file returns empty seq":
    check loadSkillRegistry("/nonexistent/skills.toml") == newSeq[SkillManifest]()

  test "parses skill entries from TOML":
    let tmp = getTempDir() / "donkey_test_skills_load"
    removeDir(tmp); createDir(tmp)
    defer: removeDir(tmp)
    let path = tmp / "skills.toml"
    writeFile(path, """
[[skill]]
name        = "web-search"
version     = "1.2.0"
script      = "/skills/search.ts"
permissions = ["--allow-net"]
tools       = ["search", "fetch"]
""")
    let skills = loadSkillRegistry(path)
    require skills.len == 1
    check skills[0].name        == "web-search"
    check skills[0].version     == "1.2.0"
    check skills[0].script      == "/skills/search.ts"
    check skills[0].permissions == @["--allow-net"]
    check skills[0].tools       == @["search", "fetch"]

  test "malformed TOML returns empty seq":
    let tmp = getTempDir() / "donkey_test_skills_bad"
    removeDir(tmp); createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "skills.toml", "not valid [[toml{{")
    check loadSkillRegistry(tmp / "skills.toml") == newSeq[SkillManifest]()

  test "entry without name is skipped":
    let tmp = getTempDir() / "donkey_test_skills_noname"
    removeDir(tmp); createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "skills.toml", """
[[skill]]
version = "1.0.0"
script  = "/skills/anon.ts"
""")
    check loadSkillRegistry(tmp / "skills.toml") == newSeq[SkillManifest]()

suite "saveSkillEntry / round-trip":

  test "save then load returns same manifest":
    let tmp = getTempDir() / "donkey_test_skills_save"
    removeDir(tmp); createDir(tmp)
    defer: removeDir(tmp)
    let path = tmp / "skills.toml"
    let m = SkillManifest(
      name:        "code-runner",
      version:     "0.3.1",
      script:      "/skills/runner.ts",
      permissions: @["--allow-read", "--allow-run"],
      tools:       @["run_code"],
    )
    saveSkillEntry(path, m)
    let skills = loadSkillRegistry(path)
    require skills.len == 1
    check skills[0] == m

  test "save appends; existing entries preserved":
    let tmp = getTempDir() / "donkey_test_skills_append"
    removeDir(tmp); createDir(tmp)
    defer: removeDir(tmp)
    let path = tmp / "skills.toml"
    saveSkillEntry(path, SkillManifest(name: "a", version: "1.0", script: "/a.ts"))
    saveSkillEntry(path, SkillManifest(name: "b", version: "2.0", script: "/b.ts"))
    let skills = loadSkillRegistry(path)
    check skills.len == 2
    check skills[0].name == "a"
    check skills[1].name == "b"

suite "loadUserSkills":

  test "missing dir returns empty seq":
    check loadUserSkills("/nonexistent/uuid/skills") == newSeq[SkillManifest]()

  test "loads skills.toml from user dir":
    let tmp = getTempDir() / "donkey_test_user_skills"
    removeDir(tmp); createDir(tmp)
    defer: removeDir(tmp)
    let skillsDir = tmp / "skills"
    createDir(skillsDir)
    writeFile(skillsDir / "skills.toml", """
[[skill]]
name    = "my-skill"
version = "0.1.0"
script  = "/user/skill.ts"
""")
    let skills = loadUserSkills(skillsDir)
    require skills.len == 1
    check skills[0].name == "my-skill"

suite "mergeSkills":

  test "user skill overrides global by name":
    let global = @[
      SkillManifest(name: "search", version: "1.0", script: "/g/search.ts"),
      SkillManifest(name: "calc",   version: "1.0", script: "/g/calc.ts"),
    ]
    let user = @[
      SkillManifest(name: "search", version: "2.0", script: "/u/search.ts"),
    ]
    let merged = mergeSkills(global, user)
    check merged.len == 2
    let s = merged.filterIt(it.name == "search")[0]
    check s.version == "2.0"
    check s.script  == "/u/search.ts"

  test "user-only skill is added":
    let global = @[SkillManifest(name: "a", version: "1.0", script: "/a.ts")]
    let user   = @[SkillManifest(name: "b", version: "1.0", script: "/b.ts")]
    let merged = mergeSkills(global, user)
    check merged.len == 2

  test "empty user returns global unchanged":
    let global = @[SkillManifest(name: "x", version: "1.0", script: "/x.ts")]
    check mergeSkills(global, newSeq[SkillManifest]()) == global
