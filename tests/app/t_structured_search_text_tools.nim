import std/[json, os, strutils, times, unittest]
import donkey/app/tools/search_tools
import donkey/app/tools/text_tools
import donkey/core/tooling/structured_tool_result

proc uniqueTempDir(prefix: string): string =
  getTempDir() / (prefix & "_" & $epochTime())

suite "structured search tools":

  test "performFindStructured returns typed filesystem items":
    let tmpDir = uniqueTempDir("donkey_struct_find")
    createDir(tmpDir)
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)

    writeFile(tmpDir / "alpha.nim", "echo 1\n")
    createDir(tmpDir / "nested")
    writeFile(tmpDir / "nested" / "beta.txt", "hello\n")

    let parsed = parseJson(performFindStructured(tmpDir, "*", "any", 20, tmpDir).toJson())

    check parsed["ok"].getBool()
    check parsed["status"].getStr() == "output"
    check parsed["data"]["count"].getInt() == 3
    check parsed["data"]["path"].getStr() == "."
    check parsed["data"]["items"][0].hasKey("path")
    check parsed["data"]["items"][0].hasKey("kind")

  test "performGrepStructured returns structured matches":
    let tmpFile = uniqueTempDir("donkey_struct_grep") & ".txt"
    writeFile(tmpFile, "alpha\nbeta needle\ngamma needle\n")
    defer:
      if fileExists(tmpFile):
        removeFile(tmpFile)

    let parsed = parseJson(performGrepStructured("needle", tmpFile, false, 20, parentDir(tmpFile)).toJson())

    check parsed["ok"].getBool()
    check parsed["status"].getStr() == "output"
    check parsed["data"]["path"].getStr() == extractFilename(tmpFile)
    check parsed["data"]["count"].getInt() == 2
    check parsed["data"]["matches"][0]["path"].getStr() == extractFilename(tmpFile)
    check parsed["data"]["matches"][0]["line"].getInt() == 2
    check parsed["data"]["matches"][0]["text"].getStr() == "beta needle"
    check parsed["data"]["matches"][1]["line"].getInt() == 3

  test "performGrepStructured rejects empty pattern as usage error":
    let parsed = parseJson(performGrepStructured("", ".", true, 20).toJson())

    check not parsed["ok"].getBool()
    check parsed["status"].getStr() == "usage_error"
    check parsed["error"]["message"].getStr().contains("empty pattern")

suite "structured text tools":

  test "readStructuredTextSlice returns anchored line objects":
    let tmpFile = uniqueTempDir("donkey_struct_slice") & ".txt"
    writeFile(tmpFile, "alpha\nbeta\ngamma\n")
    defer:
      if fileExists(tmpFile):
        removeFile(tmpFile)

    let parsed = parseJson(readStructuredTextSlice(tmpFile, 2, 2, parentDir(tmpFile)).toJson())

    check parsed["ok"].getBool()
    check parsed["data"]["path"].getStr() == extractFilename(tmpFile)
    check parsed["data"]["start_line"].getInt() == 2
    check parsed["data"]["end_line"].getInt() == 3
    check parsed["data"]["count"].getInt() == 2
    check parsed["data"]["lines"][0]["line"].getInt() == 2
    check parsed["data"]["lines"][0]["text"].getStr() == "beta"
    check parsed["data"]["lines"][0]["anchor"].getStr().startsWith("2#")

  test "replaceStructuredText updates file and reports replacements":
    let tmpFile = uniqueTempDir("donkey_struct_replace") & ".txt"
    writeFile(tmpFile, "alpha beta beta\n")
    defer:
      if fileExists(tmpFile):
        removeFile(tmpFile)

    let parsed = parseJson(replaceStructuredText(tmpFile, "beta", "delta", 1, parentDir(tmpFile)).toJson())

    check parsed["ok"].getBool()
    check parsed["data"]["path"].getStr() == extractFilename(tmpFile)
    check parsed["data"]["replacements"].getInt() == 1
    check parsed["data"]["changed"].getBool()
    check readFile(tmpFile) == "alpha delta beta\n"

  test "replaceStructuredText returns operational error for missing file":
    let parsed = parseJson(replaceStructuredText("/nonexistent/file.txt", "a", "b", 0).toJson())

    check not parsed["ok"].getBool()
    check parsed["status"].getStr() == "operational_error"
    check parsed["error"]["message"].getStr().contains("path not found")
