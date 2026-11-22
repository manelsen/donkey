## The TOML subset the configuration uses, parsed from a string with no
## std/streams and no global state, so the parser is gcsafe.

import std/[strutils, tables, unittest]
import donkey/config/toml

proc parsesGcsafe(text: string): TomlValueRef {.gcsafe.} =
  ## Compiles only while the parser is callable from gcsafe code.
  parseToml(text)

proc runTests*() =
  suite "toml parser":
    test "top-level keys, comments and basic types":
      let t = parsesGcsafe("""
# a comment
name = "donkey"   # trailing comment
count = 1_024
ratio = 0.5
neg = -3
on = true
off = false
""")
      check t["name"].getStr == "donkey"
      check t["count"].getInt == 1024
      check t["ratio"].getFloat == 0.5
      check t["neg"].getInt == -3
      check t["on"].getBool
      check not t["off"].getBool
      check t.hasKey("name") and not t.hasKey("missing")
      check t["count"].kind == TomlValueKind.Int

    test "strings: escapes, literal, multiline":
      const tq = "\"\"\""
      const sq = "'''"
      let t = parseToml(
        "basic = \"tab\\there \\\"quoted\\\" \\\\ back \\u00e9\"\n" &
        "literal = 'C:\\path\\no escapes'\n" &
        "multi = " & tq & "\nline one\nline two" & tq & "\n" &
        "lit_multi = " & sq & "\nraw \\n stays" & sq & "\n")
      check t["basic"].getStr == "tab\there \"quoted\" \\ back é"
      check t["literal"].getStr == "C:\\path\\no escapes"
      check t["multi"].getStr == "line one\nline two"
      check t["lit_multi"].getStr == "raw \\n stays"

    test "tables, dotted headers and dotted keys":
      let t = parseToml("""
[donkey]
home = "~/.donkey"

[security.tools.web_fetch]
allow = ["a.com", "b.com"]

[security.skills."my skill"]
allow_net = "x.org"

[sandbox]
image.name = "alpine"
""")
      check t["donkey"]["home"].getStr == "~/.donkey"
      check t["security"]["tools"]["web_fetch"]["allow"].getElems.len == 2
      check t["security"]["skills"]["my skill"]["allow_net"].getStr == "x.org"
      check t["sandbox"]["image"]["name"].getStr == "alpine"
      var names: seq[string]
      for name, node in t["security"]["tools"].tableVal.pairs:
        names.add name
        check node.kind == TomlValueKind.Table
      check names == @["web_fetch"]

    test "arrays: multiline, nested, trailing comma, comments inside":
      let t = parseToml("""
hosts = [
  "a.com",  # first
  "b.com",
]
nested = [[1, 2], ["x"]]
empty = []
""")
      let hosts = t["hosts"].getElems
      check hosts.len == 2 and hosts[1].getStr == "b.com"
      check t["nested"].getElems[0].getElems[1].getInt == 2
      check t["nested"].getElems[1].getElems[0].getStr == "x"
      check t["empty"].getElems.len == 0

    test "arrays of tables and inline tables":
      let t = parseToml("""
[[skill]]
name = "one"
tools = ["a"]

[[skill]]
name = "two"
meta = { version = "1.0", enabled = true }
""")
      let skills = t["skill"].getElems
      check skills.len == 2
      check skills[0]["name"].getStr == "one"
      check skills[1]["meta"]["version"].getStr == "1.0"
      check skills[1]["meta"]["enabled"].getBool

    test "getters fall back on a missing or different kind":
      let t = parseToml("n = 1")
      check t["n"].getStr("dflt") == "dflt"
      check t["n"].getBool(true)
      check t.getOrDefault("absent").getStr("x") == "x"

    test "invalid input raises TomlError with the line number":
      for bad in ["key = ", "= 1", "a = \"unterminated", "[unclosed", "a = 1\na = 2",
                  "x = [1, 2", "a = tru"]:
        var raised = false
        try:
          discard parseToml(bad)
        except TomlError as e:
          raised = "line" in e.msg
        check raised

when isMainModule:
  runTests()
