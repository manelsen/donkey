## Config loader contract tests — RED first, then implement loader.nim

import donkey/domain/tools/github_pure
import std/[options, os, strutils, unittest]
import donkey/config/loader
import donkey/config/types
import donkey/core/types
import donkey/core/security/dm_policy

proc runTests*() =
  suite "Config Loader":

    test "home and ~ paths follow the snapshot, not the process":
      let env = environmentOf({"HOME": "/srv/alice"})
      check resolveHome(env) == "/srv/alice/.donkey"
      check resolveHome(env.with("DONKEY_HOME", "/opt/donkey")) == "/opt/donkey"
      check expandHome("~", env) == "/srv/alice"
      check expandHome("~/paddocks", env) == "/srv/alice/paddocks"
      check expandHome("/abs/~/x", env) == "/abs/~/x"
      let tmp = getTempDir() / "t_loader_home_tilde.toml"
      writeFile(tmp, "[donkey]\npaddocks = \"~/pads\"\nlog_file = \"~/d.log\"\n")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, env)
      check cfg.home == "/srv/alice/.donkey"
      check cfg.paddocks == "/srv/alice/pads"
      check cfg.logFile == "/srv/alice/d.log"

    test "resolveHomeFromEnv prefers explicit env value":
      check resolveHomeFromEnv("/tmp/donkey_home_x") == "/tmp/donkey_home_x"

    test "parseSandboxMode maps docker/oci and defaults unknown to none":
      check parseSandboxMode("docker").get() == smOci
      check parseSandboxMode("oci").get() == smOci
      check parseSandboxMode("wasm").get() == smWasm
      check parseSandboxMode("wasmer").isNone
      check parseSandboxMode("weird").isNone

    test "loadTomlConfig returns none for missing file":
      check loadTomlConfig("/tmp/donkey_nonexistent_12345.toml").isNone

    test "the environment snapshot is kept in the config":
      let env = environmentOf({"DONKEY_HTTP_PORT": "9000"})
      check loadConfig("/tmp/donkey_nonexistent_12345.toml", env).env.get("DONKEY_HTTP_PORT") == "9000"

    test "returns defaults when config file is missing":
      let cfg = loadConfig("/tmp/donkey_nonexistent_12345.toml", Environment())
      check cfg.logLevel == lvlInfo
      check cfg.paddocks.endsWith("paddocks")
      check cfg.home.len > 0

    test "respects DONKEY_HOME env override":
      let cfg = loadConfig("/tmp/donkey_nonexistent_12345.toml",
                           environmentOf({"DONKEY_HOME": "/tmp/donkey_test_home"}))
      check cfg.home == "/tmp/donkey_test_home"
      check cfg.paddocks == "/tmp/donkey_test_home/paddocks"

    test "parseDmPolicy accepts open/pairing/allowlist":
      check parseDmPolicy("open").get() == DmPolicyOpen
      check parseDmPolicy("pairing").get() == DmPolicyPairing
      check parseDmPolicy("allowlist").get() == DmPolicyAllowlist
      check parseDmPolicy("nonsense").isNone

    test "malformed TOML does not silently fall back to open DM policy":
      let tmp = getTempDir() / "t_loader_malformed.toml"
      writeFile(tmp, "[security\ndm_policy = \"open\"\n")
      defer: removeFile(tmp)
      check loadConfig(tmp, Environment()).invalidDmPolicy.len > 0

    test "[github]: the write policy per repository (E11.3)":
      let tmp = getTempDir() / "t_loader_github_policy.toml"
      writeFile(tmp, """
[github]
default = "deny"

[github.repos."acme/site"]
comment = "allow"
create_issue = "ask"
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.githubPolicyError == ""
      check cfg.githubPolicy.decide("acme/site", "comment") == gpAllow
      check cfg.githubPolicy.decide("acme/site", "close_issue") == gpDeny
      check cfg.githubPolicy.decide("other/x", "comment") == gpDeny

    test "no [github]: every write asks; a bad policy asks too, and says why":
      check loadConfig("/tmp/donkey_nonexistent_12345.toml", Environment())
        .githubPolicy.decide("o/r", "comment") == gpAsk
      let tmp = getTempDir() / "t_loader_github_bad.toml"
      writeFile(tmp, "[github]\ndefault = \"maybe\"\n")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.githubPolicyError.len > 0
      check cfg.githubPolicy.decide("o/r", "comment") == gpAsk

    test "invalid dm_policy is recorded for startup rejection":
      let tmp = getTempDir() / "t_loader_bad_dm_policy.toml"
      writeFile(tmp, """
[security]
dm_policy = "nonsense"
""")
      defer: removeFile(tmp)
      check loadConfig(tmp, Environment()).invalidDmPolicy == "nonsense"

    test "invalid DONKEY_DM_POLICY is recorded for startup rejection":
      let cfg = loadConfig("/tmp/donkey_nonexistent_12345.toml",
                           environmentOf({"DONKEY_DM_POLICY": "nonsense"}))
      check cfg.invalidDmPolicy == "nonsense"

    test "valid env dm_policy clears an invalid TOML value":
      let tmp = getTempDir() / "t_loader_dm_env_override.toml"
      writeFile(tmp, """
[security]
dm_policy = "nonsense"
""")
      let cfg = loadConfig(tmp, environmentOf({"DONKEY_DM_POLICY": "open"}))
      removeFile(tmp)
      check cfg.dmPolicy == DmPolicyOpen
      check cfg.invalidDmPolicy.len == 0

    test "empty dm_policy is rejected instead of fail-open":
      let tmp = getTempDir() / "t_loader_empty_dm_policy.toml"
      writeFile(tmp, """
[security]
dm_policy = ""
""")
      defer: removeFile(tmp)
      check loadConfig(tmp, Environment()).invalidDmPolicy.len > 0

    test "reads dm_policy from the security section":
      let tmp = getTempDir() / "t_loader_dm_policy.toml"
      writeFile(tmp, """
[security]
dm_policy = "allowlist"
""")
      defer: removeFile(tmp)
      check loadConfig(tmp, Environment()).dmPolicy == DmPolicyAllowlist

    test "DONKEY_DM_POLICY overrides the config file":
      let tmp = getTempDir() / "t_loader_dm_env.toml"
      writeFile(tmp, """
[security]
dm_policy = "open"
""")
      let cfg = loadConfig(tmp, environmentOf({"DONKEY_DM_POLICY": "allowlist"}))
      removeFile(tmp)
      check cfg.dmPolicy == DmPolicyAllowlist

    test "reads log_level from toml":
      let tmp = getTempDir() / "t_loader_loglevel.toml"
      writeFile(tmp, """
[donkey]
log_level = "debug"
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.logLevel == lvlDebug

    test "unknown log_level falls back to info":
      let tmp = getTempDir() / "t_loader_badlevel.toml"
      writeFile(tmp, """
[donkey]
log_level = "nonsense"
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.logLevel == lvlInfo

    test "reads custom log_file":
      let tmp = getTempDir() / "t_loader_logfile.toml"
      writeFile(tmp, """
[donkey]
log_file = "/var/log/donkey.log"
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.logFile == "/var/log/donkey.log"

    test "expands tilde in log_file and paddocks":
      let tmp = getTempDir() / "t_loader_tilde.toml"
      writeFile(tmp, """
[donkey]
log_file = "~/var/donkey.log"
paddocks = "~/work/paddocks"
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check not cfg.logFile.startsWith("~")
      check not cfg.paddocks.startsWith("~")

    test "reads custom paddocks path":
      let tmp = getTempDir() / "t_loader_paddocks.toml"
      writeFile(tmp, """
[donkey]
paddocks = "/srv/donkey/paddocks"
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.paddocks == "/srv/donkey/paddocks"

    test "invalid TOML falls back to defaults without crashing":
      let tmp = getTempDir() / "t_loader_broken.toml"
      writeFile(tmp, "this is { not valid } toml !!!")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.logLevel == lvlInfo  # defaults intact

    test "default sandbox mode is none":
      let cfg = loadConfig("/tmp/donkey_nonexistent_12345.toml", Environment())
      check cfg.sandboxMode == smNone
      check not cfg.sandboxAllowHostFallback
      check not cfg.sandboxAllowNetwork
      check cfg.sandboxReadOnlyRootfs

    test "reads sandbox mode oci":
      let tmp = getTempDir() / "t_loader_sandbox.toml"
      writeFile(tmp, """
[donkey]
log_level = "info"

[sandbox]
mode = "oci"
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.sandboxMode == smOci

    test "tracks invalid removed sandbox mode":
      let tmp = getTempDir() / "t_loader_sandbox_wasmer.toml"
      writeFile(tmp, """
[sandbox]
mode = "wasmer"
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.sandboxMode == smNone
      check cfg.invalidSandboxMode == "wasmer"

    test "reads custom sandbox image":
      let tmp = getTempDir() / "t_loader_sbimage.toml"
      writeFile(tmp, """
[sandbox]
mode = "docker"
runtime = "podman"
image = "debian:bookworm-slim"
allow_host_fallback = true
allow_network = true
read_only_rootfs = false
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.sandboxMode  == smOci
      check cfg.sandboxRuntimeCmd == "podman"
      check cfg.sandboxImage == "debian:bookworm-slim"
      check cfg.sandboxAllowHostFallback
      check cfg.sandboxAllowNetwork
      check not cfg.sandboxReadOnlyRootfs

    test "unknown sandbox mode falls back to none":
      let tmp = getTempDir() / "t_loader_sbunk.toml"
      writeFile(tmp, """
[sandbox]
mode = "kubernetes"
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.sandboxMode == smNone
      check cfg.invalidSandboxMode == "kubernetes"

    test "default sandbox image is alpine":
      let tmp = getTempDir() / "t_loader_sbdefimg.toml"
      writeFile(tmp, """
[sandbox]
mode = "docker"
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.sandboxImage == "alpine"
      check cfg.sandboxRuntimeCmd == "docker"

    test "blank log_file and paddocks keep defaults":
      let tmp = getTempDir() / "t_loader_blank_paths.toml"
      writeFile(tmp, """
[donkey]
log_file = "   "
paddocks = "   "
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.logFile.endsWith("donkey.log")
      check cfg.paddocks.endsWith("paddocks")

    test "blank sandbox image keeps default":
      let tmp = getTempDir() / "t_loader_blank_image.toml"
      writeFile(tmp, """
[sandbox]
mode = "docker"
image = "   "
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.sandboxMode == smOci
      check cfg.sandboxImage == "alpine"

    test "reads security web_allowlist from toml":
      let tmp = getTempDir() / "t_loader_security.toml"
      writeFile(tmp, """
[security]
web_allowlist = ["example.com", "api.github.com"]
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.webAllowlist == @["example.com", "api.github.com"]

    test "DONKEY_WEB_ALLOWLIST overrides toml":
      let tmp = getTempDir() / "t_loader_security_env.toml"
      writeFile(tmp, """
[security]
web_allowlist = ["example.com"]
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, environmentOf(
        {"DONKEY_WEB_ALLOWLIST": "docs.nim-lang.org, api.github.com"}))
      check cfg.webAllowlist == @["docs.nim-lang.org", "api.github.com"]

    test "reads tool and skill network policies":
      let tmp = getTempDir() / "t_loader_security_policy.toml"
      writeFile(tmp, """
[security.tools.fetch]
allow = ["docs.nim-lang.org/manual", "api.github.com/repos/"]

[security.skills.github_skill]
allow_net = ["api.github.com"]
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.toolWebPolicy.len == 1
      check cfg.toolWebPolicy[0].toolName == "fetch"
      check cfg.toolWebPolicy[0].allow[0].host == "docs.nim-lang.org"
      check cfg.toolWebPolicy[0].allow[0].pathPrefix == "/manual"
      check cfg.skillNetPolicy.len == 1
      check cfg.skillNetPolicy[0].skillName == "github_skill"
      check cfg.skillNetPolicy[0].allowNetHosts == @["api.github.com"]

    test "reads [[bots]], keeps the good ones and says what is wrong with the rest":
      let tmp = getTempDir() / "t_loader_bots.toml"
      writeFile(tmp, """
[[bots]]
name = "suporte"
channel = "telegram"
token_env = "TELEGRAM_TOKEN_SUPORTE"
agent = "suporte"

[[bots]]
name = "vendas"
channel = "whatsapp"
phone_number_id = "1234567890"

[[bots]]
name = "quebrado"
channel = "telegram"
""")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.bots.len == 2
      check cfg.bots[0].name == "suporte" and cfg.bots[0].kind == ckTelegram
      check cfg.bots[0].tokenEnv == "TELEGRAM_TOKEN_SUPORTE"
      check cfg.bots[0].agent == "suporte"
      check cfg.bots[1].phoneNumberId == "1234567890"
      check cfg.botProblems.len == 1
      check "quebrado" in cfg.botProblems[0]

    test "no [[bots]] means only the default bots":
      let tmp = getTempDir() / "t_loader_nobots.toml"
      writeFile(tmp, "[donkey]\nlog_level = \"info\"\n")
      defer: removeFile(tmp)
      let cfg = loadConfig(tmp, Environment())
      check cfg.bots.len == 0 and cfg.botProblems.len == 0

when isMainModule:
  runTests()
