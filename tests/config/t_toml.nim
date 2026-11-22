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

    test "quotes right before the multiline closing delimiter belong to the content":
      const tq = "\"\"\""
      const sq = "'''"
      check parseToml("a = " & tq & "\"X\"" & tq)["a"].getStr == "\"X\""
      check parseToml("a = " & tq & "X\"\"" & tq)["a"].getStr == "X\"\""
      check parseToml("a = " & sq & "'X'" & sq)["a"].getStr == "'X'"
      check parseToml("a = " & sq & "X''" & sq)["a"].getStr == "X''"

    test "a line-ending backslash must really end the line":
      const tq = "\"\"\""
      check parseToml("a = " & tq & "abc\\   \n   def" & tq)["a"].getStr == "abcdef"
      expect TomlError:
        discard parseToml("a = " & tq & "abc\\ def" & tq)

    test "underscores in numbers must sit between digits":
      check parseToml("n = 1_024")["n"].getInt == 1024
      check parseToml("n = 0xdead_beef")["n"].getInt == 0xdeadbeef
      for bad in ["n = 1__0", "n = _10", "n = 10_", "n = 1_.5", "n = 0x_ff"]:
        expect TomlError:
          discard parseToml(bad)

    test "an inline table is closed once written":
      expect TomlError:
        discard parseToml("security = { dm_policy = \"pairing\" }\nsecurity.web = 1")
      expect TomlError:
        discard parseToml("a = { b = { c = 1 } }\n[a.b]\nd = 2")
      check parseToml("a = { b = 1, c.d = 2 }")["a"]["c"]["d"].getInt == 2

    test "a static array cannot be extended by an array-of-tables header":
      expect TomlError:
        discard parseToml("tool = []\n[[tool]]\ncommand = \"uvx\"")
      let t = parseToml("[[tool]]\nname = \"a\"\n[[tool]]\nname = \"b\"")
      check t["tool"].getElems.len == 2

    test "a table can be defined only once":
      expect TomlError:
        discard parseToml("[security]\na = 1\n[security]\nb = 2")
      expect TomlError:
        discard parseToml("[fruit]\napple.color = \"red\"\n[fruit.apple]\nx = 1")
      ## A dotted key defines an implicit table it passes through.
      expect TomlError:
        discard parseToml("[a.b.c]\n[a]\nb.d = 1\n[a.b]\ne = 2")
      ## Implicit parents may be defined later, and [[x]] elements are distinct.
      check parseToml("[a.b]\nc = 1\n[a]\nd = 2")["a"]["d"].getInt == 2
      check parseToml("[[s]]\n[s.meta]\nk = 1\n[[s]]\n[s.meta]\nk = 2")["s"].getElems.len == 2

when isMainModule:
  runTests()
