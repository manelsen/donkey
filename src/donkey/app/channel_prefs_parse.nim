## Channel preference parsing — pure functions over raw text.
## Lives in app so core stays free of the TOML parser.
## Orchestrator imports THIS instead of common_runtime.

import ../config/toml
import ../core/providers/smart_routing  ## for normalizeBudgetPolicy
import ../core/types                    ## ChannelPrefs, defaultChannelPrefs

import ../core/pipeops

proc tryParseChannelPrefs*(preferencesMd: string): Result[ChannelPrefs, string] =
  ## The preferences, or why they cannot be read: a malformed document is an
  ## error here, not the defaults. Missing keys keep their defaults.
  var prefs = defaultChannelPrefs()
  if preferencesMd.len == 0:
    return ok(prefs)
  try:
    let t = parseToml(preferencesMd)
    for key in ["provider", "model", "thinking", "budget", "reasoning"]:
      if t.hasKey(key) and t[key].kind != TomlValueKind.String:
        return err("PREFERENCES.md: `" & key & "` must be a string")
    if t.hasKey("provider"):
      prefs.provider = t["provider"].getStr()
    if t.hasKey("model"):
      prefs.model = t["model"].getStr()
    if t.hasKey("thinking"):
      prefs.thinking = t["thinking"].getStr()
    if t.hasKey("budget"):
      prefs.budget = normalizeBudgetPolicy(t["budget"].getStr())
    if t.hasKey("reasoning"):
      prefs.reasoning = t["reasoning"].getStr()
    ok(prefs)
  except CatchableError as e:
    err("PREFERENCES.md: " & e.msg)

proc parseSmartRoutingPrefs*(preferencesMd: string): SmartRoutingPrefs {.raises: [].} =
  ## The routing preferences, read as TOML like every other preference, so
  ## escapes, comments and every string form mean what they mean in TOML. A
  ## document that is not valid TOML is still read line by line
  ## (`scanSmartRoutingPrefs`) so the turn can be routed.
  if preferencesMd.len == 0:
    return defaultSmartRoutingPrefs()
  try:
    let t = parseToml(preferencesMd)
    var entries: seq[(string, string)]
    for key in ["provider", "model", "thinking", "budget"]:
      if t.hasKey(key) and t[key].kind == TomlValueKind.String:
        entries.add((key, t[key].getStr()))
    smartRoutingPrefsFrom(entries)
  except CatchableError:
    scanSmartRoutingPrefs(preferencesMd)

proc parseChannelPrefs*(preferencesMd: string): ChannelPrefs =
  ## For callers that must go on with something (building a turn): a
  ## malformed document reads as the defaults. Commands use
  ## tryParseChannelPrefs and report the error instead.
  result = defaultChannelPrefs()
  if preferencesMd.len == 0:
    return
  try:
    let t = parseToml(preferencesMd)
    if t.hasKey("provider"):
      result.provider = t["provider"].getStr()
    if t.hasKey("model"):
      result.model = t["model"].getStr()
    if t.hasKey("thinking"):
      result.thinking = t["thinking"].getStr("off")
    if t.hasKey("budget"):
      result.budget = normalizeBudgetPolicy(t["budget"].getStr("balanced"))
    if t.hasKey("reasoning"):
      result.reasoning = t["reasoning"].getStr("on")
  except CatchableError:
    discard