import std/[json, os, sequtils, sets, strutils, unittest]
import donkey/app/tools/fs_tools
import donkey/core/tooling/structured_tool_result

proc parseEnvelope(toolResult: StructuredToolResult): JsonNode =
  parseJson(toolResult.toJson())

suite "structured filesystem tool core":
  var paddock: string

  setup:
    paddock = getTempDir() / "donkey_fs_structured_test"
    try:
      if dirExists(paddock): removeDir(paddock)
    except OSError:
      discard
    createDir(paddock)
    createDir(paddock / "docs")
    createDir(paddock / "docs" / "nested")
    writeFile(paddock / "alpha.txt", "alpha\nbeta\n")
    writeFile(paddock / "docs" / "notes.txt", "hello\nworld\n")
    writeFile(paddock / "docs" / "nested" / "data.json", "{\"ok\":true,\"count\":2}")

  teardown:
    try:
      if dirExists(paddock): removeDir(paddock)
    except OSError:
      discard

  test "fs_list returns structured metadata with paddock-relative paths":
    let parsed = parseEnvelope(performFsList(".", paddock, recursive = true))

    check parsed["ok"].getBool()
    check parsed["status"].getStr() == "output"
    check parsed["data"]["base_path"].getStr() == "."

    let items = parsed["data"]["items"].getElems()
    let paths = items.mapIt(it["path"].getStr()).toHashSet()
    check "alpha.txt" in paths
    check "docs" in paths
    check "docs/notes.txt" in paths
    check "docs/nested/data.json" in paths
    check items.allIt(it.hasKey("kind"))
    check items.allIt(it.hasKey("size"))
    check items.allIt(it.hasKey("mtime"))

  test "fs_read supports text, lines, json and bytes_meta":
    let textParsed = parseEnvelope(performFsRead("alpha.txt", paddock, "text"))
    check textParsed["data"]["text"].getStr() == "alpha\nbeta\n"

    let linesParsed = parseEnvelope(performFsRead("alpha.txt", paddock, "lines"))
    check linesParsed["data"]["lines"].len == 2
    check linesParsed["data"]["lines"][1].getStr() == "beta"

    let jsonParsed = parseEnvelope(performFsRead("docs/nested/data.json", paddock, "json"))
    check jsonParsed["data"]["value"]["ok"].getBool()
    check jsonParsed["data"]["value"]["count"].getInt() == 2

    let bytesParsed = parseEnvelope(performFsRead("docs/nested/data.json", paddock, "bytes_meta"))
    check bytesParsed["data"]["size"].getInt() > 0

  test "fs_write supports create append replace and json payloads":
    let created = parseEnvelope(performFsWrite("created.txt", paddock, "create", %"first line"))
    check created["ok"].getBool()
    check readFile(paddock / "created.txt") == "first line"

    let appended = parseEnvelope(performFsWrite("created.txt", paddock, "append", %*["second", "third"], format = "lines"))
    check appended["ok"].getBool()
    check readFile(paddock / "created.txt") == "first linesecond\nthird\n"

    let replaced = parseEnvelope(performFsWrite("created.txt", paddock, "replace", %"reset"))
    check replaced["ok"].getBool()
    check readFile(paddock / "created.txt") == "reset"

    let jsonWritten = parseEnvelope(performFsWrite("obj.json", paddock, "create", %*{"name": "donkey", "n": 2}, format = "json"))
    check jsonWritten["ok"].getBool()
    let writtenObj = parseJson(readFile(paddock / "obj.json"))
    check writtenObj["name"].getStr() == "donkey"

  test "mkdir copy move and remove operate on files and trees":
    let mkdirParsed = parseEnvelope(performFsMkdir("tmp/out", paddock, parents = true))
    check mkdirParsed["ok"].getBool()
    check dirExists(paddock / "tmp" / "out")

    let copyFile = parseEnvelope(performFsCopy("alpha.txt", "tmp/out/alpha-copy.txt", paddock))
    check copyFile["ok"].getBool()
    check readFile(paddock / "tmp" / "out" / "alpha-copy.txt") == "alpha\nbeta\n"

    let copyTree = parseEnvelope(performFsCopy("docs", "tmp/docs-copy", paddock, recursive = true))
    check copyTree["ok"].getBool()
    check fileExists(paddock / "tmp" / "docs-copy" / "nested" / "data.json")

    let moved = parseEnvelope(performFsMove("tmp/out/alpha-copy.txt", "tmp/out/alpha-renamed.txt", paddock))
    check moved["ok"].getBool()
    check fileExists(paddock / "tmp" / "out" / "alpha-renamed.txt")
    check not fileExists(paddock / "tmp" / "out" / "alpha-copy.txt")

    let removedFile = parseEnvelope(performFsRemove("tmp/out/alpha-renamed.txt", paddock))
    check removedFile["ok"].getBool()
    check not fileExists(paddock / "tmp" / "out" / "alpha-renamed.txt")

    let removedTree = parseEnvelope(performFsRemove("tmp/docs-copy", paddock, recursive = true))
    check removedTree["ok"].getBool()
    check not dirExists(paddock / "tmp" / "docs-copy")

  test "outside-paddock operations become usage_error":
    let parsed = parseEnvelope(performFsRead("../secret.txt", paddock, "text"))
    check not parsed["ok"].getBool()
    check parsed["status"].getStr() == "usage_error"
    check parsed["error"]["message"].getStr().contains("outside paddock")
