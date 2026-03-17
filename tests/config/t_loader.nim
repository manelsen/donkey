## Config loader contract tests — RED first, then implement loader.nim

import std/[os, strutils, unittest]
import donkey/config/loader
import donkey/core/types

suite "Config Loader":

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
