## t_ctl_handler.nim — Unit tests for ctl_handler.nim
##
## Tests the Result-returning handlers without needing a full daemon boot.
## Uses temporary directories for paddocks and skill registries.

import std/[os, strutils, unittest]
import results
import donkey/core/types
import donkey/config/types
import donkey/adapters/memory/md_file
import donkey/adapters/memory/dm_allowlist
import donkey/ctl_handler
import donkey/config/environment
import donkey/config/skills_registry

# ── helpers ────────────────────────────────────────────────────────────────────

proc makeTestPaddock(): string =
  let tmp = getTempDir() / "donkey_ctl_test_" & $getCurrentProcessId()
  createDir(tmp)
  result = tmp

proc cleanupPaddock(dir: string) =
  removeDir(dir)

proc setupUserPaddock(paddockDir: string; userId: string) =
  let userDir = paddockDir / userId
  createDir(userDir)
  writeFile(userDir / "USER.md",
    "# User Profile\n" &
    "Name: Test User\n" &
    "Preferred Name: Tester\n")

proc setupSkillRegistry(path: string) =
  writeFile(path, "")

# ── ctlUserShow ────────────────────────────────────────────────────────────────

proc runTests*() =
  suite "ctl_handler — ctlUserShow":

    test "returns err for nonexistent user":
      let tmp = makeTestPaddock()
      try:
        let mem = MdFileAdapter(paddocksDir: tmp)
        let r = ctlUserShow(mem, "nonexistent")
        check r.isErr
        check "User not found" in r.error
      finally:
        cleanupPaddock(tmp)

    test "returns ok for existing user with profile":
      let tmp = makeTestPaddock()
      try:
        setupUserPaddock(tmp, "alice")
        let mem = MdFileAdapter(paddocksDir: tmp)
        let r = ctlUserShow(mem, "alice")
        check r.isOk
        # Output goes to stdout; we verify no error
      finally:
        cleanupPaddock(tmp)

  # ── ctlUserList ────────────────────────────────────────────────────────────────

  suite "ctl_handler — ctlUserList":

    test "reports no users on empty paddock":
      let tmp = makeTestPaddock()
      try:
        let mem = MdFileAdapter(paddocksDir: tmp)
        # Should not crash
        ctlUserList(mem)
      finally:
        cleanupPaddock(tmp)

    test "lists existing users":
      let tmp = makeTestPaddock()
      try:
        setupUserPaddock(tmp, "bob")
        setupUserPaddock(tmp, "carol")
        let mem = MdFileAdapter(paddocksDir: tmp)
        # Should not crash and should list users
        ctlUserList(mem)
      finally:
        cleanupPaddock(tmp)

  # ── ctlUserEdit ────────────────────────────────────────────────────────────────

  suite "ctl_handler — ctlUserEdit":

    test "edits a user field":
      let tmp = makeTestPaddock()
      try:
        setupUserPaddock(tmp, "dave")
        let mem = MdFileAdapter(paddocksDir: tmp)
        check ctlUserEdit(mem, "dave", "Preferred Name", "Davey").isOk
        let ctx = mem.loadContext(UserId("dave"))
        check "Davey" in ctx.userMd
      finally:
        cleanupPaddock(tmp)

    when defined(withSqlite):
      test "reports an edit that was not saved":
        let tmp = makeTestPaddock()
        try:
          setupUserPaddock(tmp, "dave")
          writeFile(tmp / "blocker", "x")
          let mem = MdFileAdapter(paddocksDir: tmp,
                                  magmaSqlitePath: tmp / "blocker" / "m.sqlite")
          check ctlUserEdit(mem, "dave", "Preferred Name", "Davey").isErr
        finally:
          cleanupPaddock(tmp)

  # ── ctlUserRevoke ──────────────────────────────────────────────────────────────

  suite "ctl_handler — ctlUserRevoke":

    test "revokes user access":
      let tmp = makeTestPaddock()
      try:
        setupUserPaddock(tmp / "paddocks", "eve")
        let mem = MdFileAdapter(paddocksDir: tmp / "paddocks")
        check ctlUserRevoke(mem, "eve", true).isOk
        let ctx = mem.loadContext(UserId("eve"))
        check "revoked" in ctx.userMd
        check not dmAllowlistOf(mem.paddocksDir).isAllowed(UserId("eve")).get
      finally:
        cleanupPaddock(tmp)

    test "restores user access":
      let tmp = makeTestPaddock()
      try:
        setupUserPaddock(tmp / "paddocks", "frank")
        let mem = MdFileAdapter(paddocksDir: tmp / "paddocks")
        check ctlUserRevoke(mem, "frank", true).isOk
        check ctlUserRevoke(mem, "frank", false).isOk
        let ctx = mem.loadContext(UserId("frank"))
        check "active" in ctx.userMd
        check dmAllowlistOf(mem.paddocksDir).isAllowed(UserId("frank")).get
      finally:
        cleanupPaddock(tmp)

  # ── ctlSkillInstall ────────────────────────────────────────────────────────────

  suite "ctl_handler — ctlSkillInstall":

    test "returns ok for valid skill install":
      let tmp = makeTestPaddock()
      try:
        let skillsPath = tmp / "skills.toml"
        setupSkillRegistry(skillsPath)
        let cfg = DonkeyConfig(
          home: tmp,
          webAllowlist: @["example.com"],
        )
        let r = ctlSkillInstall(cfg, skillsPath, "test-skill", "/bin/test", @["--allow-net=example.com"])
        check r.isOk
        # Verify the skill was written
        let skills = loadSkillRegistry(skillsPath)
        check skills.len == 1
        check skills[0].name == "test-skill"
      finally:
        cleanupPaddock(tmp)

    test "returns err for invalid permissions":
      let tmp = makeTestPaddock()
      try:
        let skillsPath = tmp / "skills.toml"
        setupSkillRegistry(skillsPath)
        let cfg = DonkeyConfig(
          home: tmp,
          webAllowlist: @["example.com"],
        )
        # Empty script path triggers validation error in saveSkillEntry
        let r = ctlSkillInstall(cfg, skillsPath, "bad-skill", "", @["--allow-net=evil.com"])
        check r.isErr
      finally:
        cleanupPaddock(tmp)

  # ── ctlSkillUpdate ─────────────────────────────────────────────────────────────

  suite "ctl_handler — ctlSkillUpdate":

    test "returns ok for valid update":
      let tmp = makeTestPaddock()
      try:
        let skillsPath = tmp / "skills.toml"
        setupSkillRegistry(skillsPath)
        let cfg = DonkeyConfig(
          home: tmp,
          webAllowlist: @["example.com"],
        )
        # Install first
        let _ = ctlSkillInstall(cfg, skillsPath, "upd-skill", "/bin/old", @["--allow-net=example.com"])
        # Update
        let r = ctlSkillUpdate(cfg, skillsPath, "upd-skill", "/bin/new", @["--allow-net=example.com"])
        check r.isOk
        # Verify update
        let skills = loadSkillRegistry(skillsPath)
        check skills.len == 1
        check skills[0].script == "/bin/new"
      finally:
        cleanupPaddock(tmp)

  # ── ctlSkillList ───────────────────────────────────────────────────────────────

  suite "ctl_handler — ctlSkillList":

    test "reports no skills on empty registry":
      let tmp = makeTestPaddock()
      try:
        let skillsPath = tmp / "skills.toml"
        setupSkillRegistry(skillsPath)
        # Should not crash
        ctlSkillList(skillsPath)
      finally:
        cleanupPaddock(tmp)

    test "lists installed skills":
      let tmp = makeTestPaddock()
      try:
        let skillsPath = tmp / "skills.toml"
        setupSkillRegistry(skillsPath)
        let cfg = DonkeyConfig(
          home: tmp,
          webAllowlist: @["example.com"],
        )
        let _ = ctlSkillInstall(cfg, skillsPath, "my-skill", "/bin/my-skill", @[])
        ctlSkillList(skillsPath)
        # Verify count
        let skills = loadSkillRegistry(skillsPath)
        check skills.len == 1
      finally:
        cleanupPaddock(tmp)

  # ── ctlStatus ──────────────────────────────────────────────────────────────────

  suite "ctl_handler — ctlStatus":

    test "returns err when daemon is not running":
      let tmp = makeTestPaddock()
      try:
        let cfg = DonkeyConfig(home: tmp)
        let r = ctlStatus(cfg)
        check r.isErr  # no daemon socket → error
      finally:
        cleanupPaddock(tmp)

proc runMcpLoginArgTests*() =
  suite "ctl mcp login options":
    test "no options: dynamic registration":
      let o = parseMcpLoginArgs(@[]).get
      check o.clientId == "" and o.secretEnv == ""

    test "a pre-registered client, with or without a secret variable":
      check parseMcpLoginArgs(@["--client-id", "app-42"]).get.clientId == "app-42"
      let o = parseMcpLoginArgs(@["--client-id", "app-42", "--client-secret-env", "MCP_SECRET"]).get
      check o.secretEnv == "MCP_SECRET"

    test "a secret without a client id, or an unknown option, is refused":
      check parseMcpLoginArgs(@["--client-secret-env", "X"]).isErr
      check parseMcpLoginArgs(@["--client-id"]).isErr
      check parseMcpLoginArgs(@["--bogus"]).isErr

    test "the secret is read from the environment by name, and must be set":
      let env = environmentOf({"MCP_SECRET": "s3cr3t"})
      let client = preregisteredFrom(parseMcpLoginArgs(@["--client-id", "a",
        "--client-secret-env", "MCP_SECRET"]).get, env).get
      check client.secret == "s3cr3t" and client.secretEnv == "MCP_SECRET"
      check preregisteredFrom(parseMcpLoginArgs(@["--client-id", "a",
        "--client-secret-env", "UNSET_VAR"]).get, env).isErr

when isMainModule:
  runTests()
  runMcpLoginArgTests()
