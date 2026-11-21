## Channel preferences stored in the user's PREFERENCES.md: the provider,
## model, thinking, budget and reasoning switches every channel reads and
## writes, plus single-key values such as channel cursors.

import std/strutils
import ../../core/pipeops
import ../../core/providers/smart_routing
import ../../domain/message
import ../../app/channel_prefs_parse
import ../../app/skill_runtime
import ../../core/commands/command_text
import ./md_file

export channel_prefs_parse.parseChannelPrefs

func donkeyHomeDir*(memory: MdFileAdapter): string =
  donkeyHomeDirFromPaddocks(memory.paddocksDir)

func userSkillsPath*(memory: MdFileAdapter; userId: UserId): string =
  skill_runtime.userSkillsPath(memory.paddockDir(userId))

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

proc getCurrentProviderModel*(memory: MdFileAdapter;
                              userId: UserId): (string, string) =
  let prefs = memory.loadChannelPrefs(userId)
  (prefs.provider, prefs.model)

proc getCurrentThinkLevel*(memory: MdFileAdapter; userId: UserId): string =
  memory.loadChannelPrefs(userId).thinking

proc getCurrentBudgetPolicy*(memory: MdFileAdapter; userId: UserId): string =
  parseSmartRoutingPrefs(memory.loadContext(userId).preferencesMd).budgetPolicy


proc buildConfigText*(memory: MdFileAdapter; userId: UserId;
                      withButtons = true): string =
  buildConfigText(memory.loadChannelPrefs(userId), withButtons)
