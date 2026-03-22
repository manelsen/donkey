## skills_registry — persist and load Deno skill entries in skills.toml.
##
## File format (TOML, one [[skill]] section per entry):
##   [[skill]]
##   name        = "fetch"
##   version     = "0.1.0"
##   script      = "/path/to/skill.ts"
##   tools       = ["fetch_url"]
##   permissions = ["--allow-net=api.example.com"]

import std/[os, strutils]
import parsetoml
import ../domain/builtin_tools
import ../core/pipeops

type
  SkillManifest* = object
    name*:        string
    version*:     string
    script*:      string
    tools*:       seq[string]
    permissions*: seq[string]

func parseAllowNetHosts*(permission: string): seq[string] =
  if not permission.startsWith("--allow-net="):
    return
  let rawHosts = permission["--allow-net=".len .. ^1]
  for host in rawHosts.split(','):
    let normalized = host.strip().toLowerAscii()
    if normalized.len > 0:
      result.add(normalized)

func validateDangerousPermissions*(permissions: seq[string]): Result[void, string] =
  ## Rejects permissions that are unconditionally unsafe regardless of allowlist.
  ## Called by saveSkillEntry as a last-resort guard.
  for permission in permissions:
    case permission
    of "-A", "--allow-all":
      return err("Error: unrestricted Deno permissions are not allowed for skills.")
    of "--allow-net", "--allow-net=":
      return err("Error: --allow-net must declare explicit hosts.")
    else:
      discard
    if permission.startsWith("--allow-net="):
      let hosts = parseAllowNetHosts(permission)
      if hosts.len == 0:
        return err("Error: --allow-net must declare explicit hosts.")
      if "*" in hosts:
        return err("Error: wildcard --allow-net is not allowed for skills.")
  ok()

func validateSkillPermissions*(permissions: seq[string];
                               webAllowlist: seq[string]): Result[seq[string], string] =
  for permission in permissions:
    case permission
    of "-A", "--allow-all":
      return err("Error: unrestricted Deno permissions are not allowed for skills.")
    of "--allow-net", "--allow-net=":
      return err("Error: --allow-net must declare explicit hosts.")
    else:
      discard

    if permission.startsWith("--allow-net="):
      let hosts = parseAllowNetHosts(permission)
      if hosts.len == 0:
        return err("Error: --allow-net must declare explicit hosts.")
      if "*" in hosts:
        return err("Error: wildcard --allow-net is not allowed for skills.")
      if webAllowlist.len > 0:
        for host in hosts:
          var allowed = false
          for allowHost in webAllowlist:
            if hostMatchesAllowlist(host, allowHost):
              allowed = true
              break
          if not allowed:
            return err("Error: skill host '" & host & "' is outside the configured web allowlist.")

  ok(permissions)

proc saveSkillEntry*(path: string; m: SkillManifest): Result[void, string] =
  ## Appends one [[skill]] section to the TOML file at `path`.
  ## Creates the file (and parent dirs) if it does not exist.
  ## Returns Err without writing if permissions contain unconditionally unsafe flags.
  ? validateDangerousPermissions(m.permissions)
  createDir(parentDir(path))
  var f = open(path, fmAppend)
  defer: f.close()
  f.writeLine("\n[[skill]]")
  f.writeLine("name    = \"" & m.name & "\"")
  f.writeLine("version = \"" & m.version & "\"")
  f.writeLine("script  = \"" & m.script & "\"")
  proc tomlStrArray(items: seq[string]): string =
    result = "["
    for i, s in items:
      if i > 0: result.add(", ")
      result.add("\"" & s & "\"")
    result.add("]")
  if m.tools.len > 0:
    f.writeLine("tools       = " & tomlStrArray(m.tools))
  if m.permissions.len > 0:
    f.writeLine("permissions = " & tomlStrArray(m.permissions))
  ok()

proc loadSkillRegistry*(path: string): seq[SkillManifest] =
  ## Reads all [[skill]] entries from the TOML file at `path`.
  ## Returns empty seq if file does not exist or contains no entries.
  if not fileExists(path):
    return @[]
  let t = parsetoml.parseFile(path)
  if not t.hasKey("skill"):
    return @[]
  for node in t["skill"].getElems():
    var m = SkillManifest(
      name:    node.getOrDefault("name").getStr(""),
      version: node.getOrDefault("version").getStr("0.1.0"),
      script:  node.getOrDefault("script").getStr(""),
    )
    if node.hasKey("tools"):
      for a in node["tools"].getElems(): m.tools.add(a.getStr(""))
    if node.hasKey("permissions"):
      for a in node["permissions"].getElems(): m.permissions.add(a.getStr(""))
    if m.name.len > 0 and m.script.len > 0:
      result.add(m)

proc loadUserSkills*(skillsDir: string): seq[SkillManifest] =
  ## Loads skills from a user-specific skills directory.
  ## Expects a skills.toml inside skillsDir, or individual .toml files.
  let tomlPath = skillsDir / "skills.toml"
  if fileExists(tomlPath):
    return loadSkillRegistry(tomlPath)
  ## Also accept a flat directory of individual .ts skill scripts with metadata
  ## stored alongside. For now: if no skills.toml, return empty.
  return @[]

proc mergeSkills*(base, extra: seq[SkillManifest]): seq[SkillManifest] =
  ## Merges two skill lists. Entries in `extra` override entries in `base`
  ## by name. Returns a combined list with overrides applied.
  result = base
  for e in extra:
    var found = false
    for i in 0 ..< result.len:
      if result[i].name == e.name:
        result[i] = e
        found = true
        break
    if not found:
      result.add(e)
