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

export channel_prefs_parse.parseChannelPrefs, channel_prefs_parse.tryParseChannelPrefs

func donkeyHomeDir*(memory: MdFileAdapter): string =
  donkeyHomeDirFromPaddocks(memory.paddocksDir)

func userSkillsPath*(memory: MdFileAdapter; userId: UserId): string =
  skill_runtime.userSkillsPath(memory.paddockDir(userId))

proc readPreferences*(memory: MdFileAdapter; userId: UserId): Result[string, string] =
  ## PREFERENCES.md as the store holds it, or why it cannot be read: the
  ## graph when MAGMA is ready, the file without a graph (missing reads as
  ## empty), an error when the graph is unavailable or the file unreadable.
  ## Unlike loadContext, a failed read never looks like default preferences.
  try:
    memory.storedPreferences(userId)
  except CatchableError as e:
    err("PREFERENCES.md: " & e.msg)

proc loadChannelPrefs*(memory: MdFileAdapter; userId: UserId): Result[ChannelPrefs, string] =
  tryParseChannelPrefs(? memory.readPreferences(userId))

func preferenceKey(line: string): string =
  ## The key of a `key = value` line; "" for blanks, comments and other text.
  let trimmed = line.strip
  if trimmed.len == 0 or trimmed[0] == '#':
    return ""
  let eq = trimmed.find('=')
  if eq < 0: "" else: trimmed[0 ..< eq].strip

func parsePreferenceString*(preferencesMd: string; key: string): string =
  ## Reads a single `key = "value"` (or `key = value`) entry from a
  ## preferences document. Returns "" when the key is absent or malformed.
  ## Used for values that are not part of ChannelPrefs (e.g. cursors).
  for line in preferencesMd.splitLines():
    if preferenceKey(line) != key:
      continue
    let trimmed = line.strip
    let eq = trimmed.find('=')
    var value = trimmed[eq + 1 .. ^1].strip
    if value.len >= 2 and value[0] == '"' and value[^1] == '"':
      value = value[1 .. ^2]
    return value
  ""

func setPreferences*(preferencesMd: string;
                     entries: openArray[(string, string)]): string =
  ## The document with each `key = "value"` set: lines whose key is exactly
  ## that key are replaced (a longer key such as `model_timeout` is another
  ## setting), and a missing key is appended. Other lines are kept.
  var lines = if preferencesMd.len == 0: @[] else: preferencesMd.splitLines()
  for (key, value) in entries:
    let entry = key & " = \"" & value & "\""
    var found = false
    var kept: seq[string]
    for line in lines:
      if preferenceKey(line) == key:
        if not found:
          kept.add entry
          found = true
      else:
        kept.add line
    if not found:
      kept.add entry
    lines = kept
  lines.join("\n")

proc loadChannelPreference*(memory: MdFileAdapter;
                            userId: UserId;
                            key: string): Result[string, string] =
  ## Reads one preference value by key, without parsing the whole document;
  ## "" when the key is absent.
  ok(parsePreferenceString(? memory.readPreferences(userId), key))

proc saveChannelPreferences*(memory: MdFileAdapter;
                             userId: UserId;
                             entries: openArray[(string, string)]):
                             Result[void, string] {.discardable.} =
  ## Sets one or more `key = "value"` preferences in a single read and a
  ## single write, so they are saved together or not at all. The current
  ## preferences are read from the store itself: when they cannot be read
  ## nothing is saved, instead of merging over an old export.
  let current = ? memory.storedPreferences(userId)
  memory.savePreferences(userId, setPreferences(current, entries))

proc saveChannelPreference*(memory: MdFileAdapter;
                            userId: UserId;
                            key, value: string): Result[void, string]
                            {.discardable.} =
  memory.saveChannelPreferences(userId, [(key, value)])

proc getCurrentProviderModel*(memory: MdFileAdapter;
                              userId: UserId): Result[(string, string), string] =
  let prefs = ? memory.loadChannelPrefs(userId)
  ok((prefs.provider, prefs.model))

proc getCurrentThinkLevel*(memory: MdFileAdapter; userId: UserId): Result[string, string] =
  ok((? memory.loadChannelPrefs(userId)).thinking)

proc getCurrentBudgetPolicy*(memory: MdFileAdapter; userId: UserId): Result[string, string] =
  let doc = ? memory.readPreferences(userId)
  discard ? tryParseChannelPrefs(doc)
  ok(parseSmartRoutingPrefs(doc).budgetPolicy)

proc buildConfigText*(memory: MdFileAdapter; userId: UserId;
                      withButtons = true): Result[string, string] =
  ok(buildConfigText(? memory.loadChannelPrefs(userId), withButtons))
