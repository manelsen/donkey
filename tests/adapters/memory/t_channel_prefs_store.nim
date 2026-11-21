## Setting a preference replaces the line with exactly that key: a key that
## merely starts with it (`model_timeout` for `model`) is another setting.

import std/[strutils, unittest]
import donkey/adapters/memory/channel_prefs_store

proc runTests*() =
  suite "channel preference writes":
    test "only the exact key is replaced":
      let doc = "model_timeout = \"30\"\nmodel = \"old\""
      let updated = setPreferences(doc, [("model", "new")])
      check parsePreferenceString(updated, "model") == "new"
      check parsePreferenceString(updated, "model_timeout") == "30"
      check updated.count("model = ") == 1

    test "a missing key is appended and comments are kept":
      let updated = setPreferences("# mine\nprovider = \"x\"", [("model", "m")])
      check updated.startsWith("# mine")
      check parsePreferenceString(updated, "provider") == "x"
      check parsePreferenceString(updated, "model") == "m"

    test "spacing around = does not hide the key, and duplicates collapse":
      let updated = setPreferences("model=\"a\"\n  model   =  \"b\"", [("model", "c")])
      check updated == "model = \"c\""
      check "\"a\"" notin updated and "\"b\"" notin updated

    test "several keys are set in one pass":
      let updated = setPreferences("", [("provider", "p"), ("model", "m")])
      check parsePreferenceString(updated, "provider") == "p"
      check parsePreferenceString(updated, "model") == "m"

when isMainModule:
  runTests()
