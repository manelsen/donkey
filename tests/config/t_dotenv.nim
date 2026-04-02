## Tests for config/dotenv — .env file loading.

import std/[unittest, os, strutils]
import ../../src/donkey/config/dotenv

suite "config/dotenv - loadEnvFile":

  test "loads simple KEY=VALUE":
    let tmpFile = getTempDir() / "test_env_simple.env"
    writeFile(tmpFile, "FOO=bar\nBAZ=qux\n")
    defer: removeFile(tmpFile)

    let count = loadEnvFile(tmpFile)
    check count == 2
    check getEnv("FOO") == "bar"
    check getEnv("BAZ") == "qux"
    # Cleanup
    putEnv("FOO", "")
    putEnv("BAZ", "")

  test "ignores comments":
    let tmpFile = getTempDir() / "test_env_comments.env"
    writeFile(tmpFile, "# this is a comment\nFOO=bar\n# another\n")
    defer: removeFile(tmpFile)

    let count = loadEnvFile(tmpFile)
    check count == 1

  test "ignores empty lines":
    putEnv("FOO_EMPTY", "")
    let tmpFile = getTempDir() / "test_env_empty.env"
    writeFile(tmpFile, "\n\nFOO_EMPTY=bar\n\n")
    defer: removeFile(tmpFile)

    let count = loadEnvFile(tmpFile)
    check count == 1
    putEnv("FOO_EMPTY", "")

  test "handles quoted values":
    putEnv("FOO_Q", "")
    putEnv("BAR_Q", "")
    let tmpFile = getTempDir() / "test_env_quoted.env"
    writeFile(tmpFile, """FOO_Q="hello world"
BAR_Q='single quotes'
""")
    defer: removeFile(tmpFile)

    let count = loadEnvFile(tmpFile)
    check count == 2
    check getEnv("FOO_Q") == "hello world"
    check getEnv("BAR_Q") == "single quotes"
    putEnv("FOO_Q", "")
    putEnv("BAR_Q", "")

  test "handles values with equals sign":
    putEnv("FOO_EQ", "")
    let tmpFile = getTempDir() / "test_env_equals.env"
    writeFile(tmpFile, "FOO_EQ=bar=baz\n")
    defer: removeFile(tmpFile)

    let count = loadEnvFile(tmpFile)
    check count == 1
    check getEnv("FOO_EQ") == "bar=baz"
    putEnv("FOO_EQ", "")

  test "does not override existing env vars":
    putEnv("TEST_DONT_OVERRIDE", "original")
    let tmpFile = getTempDir() / "test_env_override.env"
    writeFile(tmpFile, "TEST_DONT_OVERRIDE=new_value\n")
    defer: removeFile(tmpFile)

    let count = loadEnvFile(tmpFile)
    check count == 0
    check getEnv("TEST_DONT_OVERRIDE") == "original"
    putEnv("TEST_DONT_OVERRIDE", "")

  test "returns 0 for nonexistent file":
    let count = loadEnvFile("/nonexistent/file.env")
    check count == 0

  test "strips whitespace around keys and values":
    putEnv("FOO_WS", "")
    let tmpFile = getTempDir() / "test_env_whitespace.env"
    writeFile(tmpFile, "  FOO_WS  =  bar  \n")
    defer: removeFile(tmpFile)

    let count = loadEnvFile(tmpFile)
    check count == 1
    check getEnv("FOO_WS") == "bar"
    putEnv("FOO_WS", "")

  test "skips lines without equals":
    putEnv("FOO_NOEQ", "")
    let tmpFile = getTempDir() / "test_env_noeq.env"
    writeFile(tmpFile, "INVALID_LINE\nFOO_NOEQ=bar\n")
    defer: removeFile(tmpFile)

    let count = loadEnvFile(tmpFile)
    check count == 1
    putEnv("FOO_NOEQ", "")

suite "config/dotenv - envFilePath":

  test "returns local path if file exists":
    let tmpDir = getTempDir() / "donkey_env_test"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "donkey.env", "X=1")
    check envFilePath(tmpDir) == tmpDir / "donkey.env"

  test "returns config dir path as fallback":
    # Just verify it returns a string ending in donkey.env
    let path = envFilePath("/nonexistent")
    check path.endsWith("donkey.env")
