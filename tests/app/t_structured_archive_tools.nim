import std/[json, os, strutils, times, unittest]
import donkey/app/tools/archive_tools
import donkey/core/tooling/structured_tool_result

proc parse(toolResult: StructuredToolResult): JsonNode =
  parseJson(toolResult.toJson())

proc uniqueTempDir(prefix: string): string =
  getTempDir() / (prefix & "_" & $epochTime())

suite "structured archive tools":

  test "performArchiveCreate and performArchiveExtract round-trip a tgz bundle":
    let paddock = uniqueTempDir("donkey_archive_roundtrip")
    createDir(paddock)
    defer:
      if dirExists(paddock):
        removeDir(paddock)

    createDir(paddock / "docs")
    writeFile(paddock / "alpha.txt", "alpha\n")
    writeFile(paddock / "docs" / "notes.txt", "structured archive\n")

    let created = parse(performArchiveCreate("bundle.tgz",
                                             @["alpha.txt", "docs"],
                                             paddock))
    check created["ok"].getBool()
    check created["data"]["archive_path"].getStr().endsWith("bundle.tgz")
    check fileExists(paddock / "bundle.tgz")

    let extracted = parse(performArchiveExtract("bundle.tgz",
                                                "restored",
                                                paddock))
    check extracted["ok"].getBool()
    check extracted["data"]["destination"].getStr().endsWith("restored")
    check fileExists(paddock / "restored" / "alpha.txt")
    check fileExists(paddock / "restored" / "docs" / "notes.txt")
    check readFile(paddock / "restored" / "docs" / "notes.txt") == "structured archive\n"

  test "performArchiveExtract rejects destination outside paddock":
    let paddock = uniqueTempDir("donkey_archive_guard")
    createDir(paddock)
    defer:
      if dirExists(paddock):
        removeDir(paddock)

    writeFile(paddock / "alpha.txt", "alpha\n")
    discard performArchiveCreate("bundle.tgz", @["alpha.txt"], paddock)

    let parsed = parse(performArchiveExtract("bundle.tgz",
                                             "../escape",
                                             paddock))

    check not parsed["ok"].getBool()
    check parsed["status"].getStr() == "usage_error"
    check parsed["error"]["message"].getStr().contains("outside paddock")

  test "performArchiveCreate rejects unsupported archive format":
    let paddock = uniqueTempDir("donkey_archive_ext")
    createDir(paddock)
    defer:
      if dirExists(paddock):
        removeDir(paddock)

    writeFile(paddock / "alpha.txt", "alpha\n")

    let parsed = parse(performArchiveCreate("bundle.rar", @["alpha.txt"], paddock))

    check not parsed["ok"].getBool()
    check parsed["status"].getStr() == "usage_error"
    check parsed["error"]["message"].getStr().contains("unsupported archive format")
