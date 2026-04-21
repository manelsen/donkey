## Config loader contract tests — RED first, then implement loader.nim

import std/[options, os, strutils, unittest]
import donkey/config/loader
import donkey/config/types
import donkey/core/types

suite "Config Loader":

  test "resolveHomeFromEnv prefers explicit env value":
    check resolveHomeFromEnv("/tmp/donkey_home_x") == "/tmp/donkey_home_x"

  test "parseSandboxMode maps docker/oci and defaults unknown to none":
    check parseSandboxMode("docker") == smOci
    check parseSandboxMode("oci") == smOci
    check parseSandboxMode("wasmer") == smWasmer
    check parseSandboxMode("weird") == smNone

  test "loadTomlConfig returns none for missing file":
    check loadTomlConfig("/tmp/donkey_nonexistent_12345.toml").isNone

  test "returns defaults when config file is missing":
    let cfg = loadConfig("/tmp/donkey_nonexistent_12345.toml")
    check cfg.logLevel == lvlInfo
    check cfg.paddocks.endsWith("paddocks")
    check cfg.home.len > 0

  test "respects DONKEY_HOME env override":
    putEnv("DONKEY_HOME", "/tmp/donkey_test_home")
    let cfg = loadConfig("/tmp/donkey_nonexistent_12345.toml")
    delEnv("DONKEY_HOME")
    check cfg.home == "/tmp/donkey_test_home"
    check cfg.paddocks == "/tmp/donkey_test_home/paddocks"

  test "reads log_level from toml":
    let tmp = getTempDir() / "t_loader_loglevel.toml"
    writeFile(tmp, """
[donkey]
log_level = "debug"
""")
    defer: removeFile(tmp)
    let cfg = loadConfig(tmp)
    check cfg.logLevel == lvlDebug

  test "unknown log_level falls back to info":
    let tmp = getTempDir() / "t_loader_badlevel.toml"
    writeFile(tmp, """
[donkey]
log_level = "nonsense"
""")
    defer: removeFile(tmp)
    let cfg = loadConfig(tmp)
    check cfg.logLevel == lvlInfo

  test "reads custom log_file":
    let tmp = getTempDir() / "t_loader_logfile.toml"
    writeFile(tmp, """
[donkey]
log_file = "/var/log/donkey.log"
""")
    defer: removeFile(tmp)
    let cfg = loadConfig(tmp)
    check cfg.logFile == "/var/log/donkey.log"

  test "expands tilde in log_file and paddocks":
    let tmp = getTempDir() / "t_loader_tilde.toml"
    writeFile(tmp, """
[donkey]
log_file = "~/var/donkey.log"
paddocks = "~/work/paddocks"
""")
    defer: removeFile(tmp)
    let cfg = loadConfig(tmp)
    check not cfg.logFile.startsWith("~")
    check not cfg.paddocks.startsWith("~")

  test "reads custom paddocks path":
    let tmp = getTempDir() / "t_loader_paddocks.toml"
    writeFile(tmp, """
[donkey]
paddocks = "/srv/donkey/paddocks"
""")
    defer: removeFile(tmp)
    let cfg = loadConfig(tmp)
    check cfg.paddocks == "/srv/donkey/paddocks"

  test "invalid TOML falls back to defaults without crashing":
    let tmp = getTempDir() / "t_loader_broken.toml"
    writeFile(tmp, "this is { not valid } toml !!!")
    defer: removeFile(tmp)
    let cfg = loadConfig(tmp)
    check cfg.logLevel == lvlInfo  # defaults intact

  test "default sandbox mode is none":
    let cfg = loadConfig("/tmp/donkey_nonexistent_12345.toml")
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
    let cfg = loadConfig(tmp)
    check cfg.sandboxMode == smOci

  test "reads sandbox mode wasmer":
    let tmp = getTempDir() / "t_loader_sandbox_wasmer.toml"
    writeFile(tmp, """
[sandbox]
mode = "wasmer"
""")
    defer: removeFile(tmp)
    let cfg = loadConfig(tmp)
    check cfg.sandboxMode == smWasmer

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
    let cfg = loadConfig(tmp)
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
    let cfg = loadConfig(tmp)
    check cfg.sandboxMode == smNone

  test "default sandbox image is alpine":
    let tmp = getTempDir() / "t_loader_sbdefimg.toml"
    writeFile(tmp, """
[sandbox]
mode = "docker"
""")
    defer: removeFile(tmp)
    let cfg = loadConfig(tmp)
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
    let cfg = loadConfig(tmp)
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
    let cfg = loadConfig(tmp)
    check cfg.sandboxMode == smOci
    check cfg.sandboxImage == "alpine"

  test "reads security web_allowlist from toml":
    let tmp = getTempDir() / "t_loader_security.toml"
    writeFile(tmp, """
[security]
web_allowlist = ["example.com", "api.github.com"]
""")
    defer: removeFile(tmp)
    let cfg = loadConfig(tmp)
    check cfg.webAllowlist == @["example.com", "api.github.com"]

  test "DONKEY_WEB_ALLOWLIST overrides toml":
    let tmp = getTempDir() / "t_loader_security_env.toml"
    writeFile(tmp, """
[security]
web_allowlist = ["example.com"]
""")
    defer:
      delEnv("DONKEY_WEB_ALLOWLIST")
      removeFile(tmp)
    putEnv("DONKEY_WEB_ALLOWLIST", "docs.nim-lang.org, api.github.com")
    let cfg = loadConfig(tmp)
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
    let cfg = loadConfig(tmp)
    check cfg.toolWebPolicy.len == 1
    check cfg.toolWebPolicy[0].toolName == "fetch"
    check cfg.toolWebPolicy[0].allow[0].host == "docs.nim-lang.org"
    check cfg.toolWebPolicy[0].allow[0].pathPrefix == "/manual"
    check cfg.skillNetPolicy.len == 1
    check cfg.skillNetPolicy[0].skillName == "github_skill"
    check cfg.skillNetPolicy[0].allowNetHosts == @["api.github.com"]
