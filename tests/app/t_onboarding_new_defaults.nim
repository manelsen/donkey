import std/[os, unittest]
import donkey/app/setup_wizard
import donkey/config/loader
import donkey/config/types
import donkey/core/app_meta

suite "setup wizard onboarding defaults":

  test "generated onboarding config loads oci sandbox and wiring defaults":
    let testDir = getTempDir() / "donkey_test_new_defaults"
    if dirExists(testDir):
      removeDir(testDir)
    createDir(testDir)
    defer:
      if dirExists(testDir):
        removeDir(testDir)

    let tomlContent = buildTomlContent(testDir, "debug")
    let tomlPath = testDir / ConfigFileName
    writeFile(tomlPath, tomlContent)

    let cfg = loadConfig(tomlPath)
    check cfg.home == testDir
    check cfg.logLevel == lvlDebug
    check cfg.sandboxMode == smOci
    check cfg.sandboxRuntimeCmd == "docker"
    check cfg.wiring == true
