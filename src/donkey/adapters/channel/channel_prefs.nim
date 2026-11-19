## Channel preference parsing and persistence for the channel runtimes.
##
## Pure parsing plus thin reads/writes over MdFileAdapter's preferences
## document. No UI or catalog dependency.

import std/strutils
import parsetoml
import results
import ../../core/pipeops
import ../../core/types
import ../../core/providers/smart_routing
import ../../adapters/memory/md_file

proc parseChannelPrefs*(preferencesMd: string): ChannelPrefs =
  result = defaultChannelPrefs()
  if preferencesMd.len == 0:
    return
  try:
    {.cast(gcsafe).}:
      let t = parsetoml.parseString(preferencesMd)
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
  except:
    discard

proc loadChannelPrefs*(memory: MdFileAdapter; userId: UserId): ChannelPrefs =
  parseChannelPrefs(memory.loadContext(userId).preferencesMd)

func parsePreferenceString*(preferencesMd: string; key: string): string =
  ## Reads a single `key = "value"` (or `key = value`) entry from a
  ## preferences document. Returns "" when the key is absent or malformed.
  ## Used for values that are not part of ChannelPrefs (e.g. cursors).
  for line in preferencesMd.splitLines():
    let trimmed = line.strip
    if trimmed.len == 0 or trimmed[0] == '#':
      continue
    let eq = trimmed.find('=')
    if eq < 0:
      continue
    if trimmed[0 ..< eq].strip != key:
      continue
    var value = trimmed[eq + 1 .. ^1].strip
    if value.len >= 2 and value[0] == '"' and value[^1] == '"':
      value = value[1 .. ^2]
    return value
  ""

proc loadChannelPreference*(memory: MdFileAdapter;
                            userId: UserId;
                            key: string): string =
  ## Reads one preference value by key, without parsing the whole document.
  parsePreferenceString(memory.loadContext(userId).preferencesMd, key)

proc saveChannelPreferences*(memory: MdFileAdapter;
                             userId: UserId;
                             entries: openArray[(string, string)]):
                             Result[void, string] {.discardable.} =
  ## Sets one or more `key = "value"` preferences in a single read and a
  ## single write, so they are saved together or not at all. The current
  ## preferences are read from the store itself: when they cannot be read
  ## nothing is saved, instead of merging over an old export.
  let current = ? memory.storedPreferences(userId)
  var lines = current.splitLines()
  for (key, value) in entries:
    var found = false
    for i in 0 ..< lines.len:
      if lines[i].startsWith(key):
        lines[i] = key & " = \"" & value & "\""
        found = true
    if not found:
      lines.add(key & " = \"" & value & "\"")
  memory.savePreferences(userId, lines.join("\n"))

proc saveChannelPreference*(memory: MdFileAdapter;
                            userId: UserId;
                            key, value: string): Result[void, string]
                            {.discardable.} =
  memory.saveChannelPreferences(userId, [(key, value)])

func savedOrError*(saved: Result[void, string]; confirmation: string): string =
  ## What to tell the user after a preference change: the confirmation only
  ## when the change was saved.
  if saved.isOk: confirmation
  else: "Não foi possível salvar: " & saved.error

proc getCurrentProviderModel*(memory: MdFileAdapter;
                              userId: UserId): (string, string) =
  let prefs = memory.loadChannelPrefs(userId)
  (prefs.provider, prefs.model)

proc getCurrentThinkLevel*(memory: MdFileAdapter; userId: UserId): string =
  memory.loadChannelPrefs(userId).thinking

proc getCurrentBudgetPolicy*(memory: MdFileAdapter; userId: UserId): string =
  parseSmartRoutingPrefs(memory.loadContext(userId).preferencesMd).budgetPolicy
