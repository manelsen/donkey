## SkillsRegistry — load/save Deno skill manifests from skills.toml.
##
## Global registry: {donkeyHome}/config/skills.toml
## Per-user override: {paddocksDir}/{uuid}/skills/skills.toml
##
## Format:
##   [[skill]]
##   name        = "web-search"    # unique key; user entry overrides global
##   version     = "1.2.0"
##   script      = "/path/to/skill.ts"
##   permissions = ["--allow-net"]
##   tools       = ["search", "fetch"]   # informational — what the skill exposes

import std/[os, sequtils, strformat, strutils, tables]
import parsetoml

type
  SkillManifest* = object
    name*:        string
    version*:     string
    script*:      string
    permissions*: seq[string]
    tools*:       seq[string]

# ── Load ──────────────────────────────────────────────────────────────────────

proc loadSkillRegistry*(path: string): seq[SkillManifest] =
  ## Reads skills.toml. Returns empty seq if file absent or malformed.
  if not fileExists(path): return @[]
  try:
    let t      = parsetoml.parseFile(path)
    let skills = t.getOrDefault("skill")
    if skills == nil or skills.kind != TomlValueKind.Array: return @[]
    for item in skills.arrayVal:
      let name = item.getOrDefault("name").getStr("")
      if name.len == 0: continue
      var m = SkillManifest(
        name:    name,
        version: item.getOrDefault("version").getStr(""),
        script:  item.getOrDefault("script").getStr(""),
      )
      let perm = item.getOrDefault("permissions")
      if perm != nil and perm.kind == TomlValueKind.Array:
        for p in perm.arrayVal: m.permissions.add(p.getStr(""))
      let tools = item.getOrDefault("tools")
      if tools != nil and tools.kind == TomlValueKind.Array:
        for tool in tools.arrayVal: m.tools.add(tool.getStr(""))
      result.add(m)
  except: discard

proc loadUserSkills*(skillsDir: string): seq[SkillManifest] =
  ## Loads skills from {uuid}/skills/skills.toml.
  loadSkillRegistry(skillsDir / "skills.toml")

# ── Save ──────────────────────────────────────────────────────────────────────

proc saveSkillEntry*(path: string; m: SkillManifest) =
  ## Appends one [[skill]] block to the registry file.
  createDir(path.parentDir())
  var s = "\n[[skill]]\n"
  s.add &"name    = \"{m.name}\"\n"
  s.add &"version = \"{m.version}\"\n"
  s.add &"script  = \"{m.script}\"\n"
  if m.permissions.len > 0:
    let ps = m.permissions.mapIt(&"\"{it}\"").join(", ")
    s.add &"permissions = [{ps}]\n"
  if m.tools.len > 0:
    let ts = m.tools.mapIt(&"\"{it}\"").join(", ")
    s.add &"tools = [{ts}]\n"
  let existing = if fileExists(path): readFile(path) else: ""
  writeFile(path, existing & s)

# ── Merge ─────────────────────────────────────────────────────────────────────

func mergeSkills*(global: seq[SkillManifest];
                  user:   seq[SkillManifest]): seq[SkillManifest] =
  ## User entries override global entries with the same name.
  ## User-only entries are appended after.
  var byName: OrderedTable[string, SkillManifest]
  for m in global: byName[m.name] = m
  for m in user:   byName[m.name] = m   ## override or insert
  for _, m in byName: result.add(m)
