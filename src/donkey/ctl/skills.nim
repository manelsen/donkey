## ctl/skills.nim — `donkey ctl tool` and `donkey ctl skill` handlers.

import std/[os, strutils, tables]
import ../core/pipeops
import ../config/types
import ../config/tools_registry
import ../config/skills_registry
import ../config/clawhub_registry

# ── ctl tool/skill commands ────────────────────────────────────────────────────

proc ctlToolInstall*(registryPath: string; command: string; args: seq[string]) =
  let entry = ToolEntry(kind: tkMcp, command: command, args: args)
  saveToolEntry(registryPath, entry)
  echo "Registered MCP server: " & command

proc ctlSkillInstall*(cfg: DonkeyConfig; skillsPath: string; name, scriptPath: string;
                      permissions: seq[string]): Result[void, string] =
  let valRes = validateSkillPermissions(permissions, cfg.webAllowlist)
  if valRes.isErr:
    echo valRes.error
    return err(valRes.error)
  let saveRes = saveSkillEntry(skillsPath, SkillManifest(
    name:        name,
    version:     "0.1.0",
    script:      scriptPath,
    permissions: permissions,
  ))
  if saveRes.isErr:
    echo saveRes.error
    return err(saveRes.error)
  echo "Registered skill: " & name & " (" & scriptPath & ")"
  ok()

proc ctlSkillList*(skillsPath: string) =
  proc echoRemoteSkillInstalls(home: string) =
    let lock = readRemoteSkillLockfile(home)
    if lock.skills.len == 0:
      echo "(no remote installs)"
      return
    for slug, entry in lock.skills.pairs:
      echo slug & " v" & entry.version & "  [remote]"

  let skills = loadSkillRegistry(skillsPath)
  if skills.len == 0:
    echo "(no local skills registered)"
  else:
    for s in skills:
      echo s.name & " v" & s.version & "  " & s.script
      if s.tools.len > 0:       echo "  tools:       " & s.tools.join(", ")
      if s.permissions.len > 0: echo "  permissions: " & s.permissions.join(", ")
  echoRemoteSkillInstalls(parentDir(skillsPath))

proc ctlSkillUpdate*(cfg: DonkeyConfig; skillsPath, name, scriptPath: string;
                     permissions: seq[string]): Result[void, string] =
  let valRes = validateSkillPermissions(permissions, cfg.webAllowlist)
  if valRes.isErr:
    echo valRes.error
    return err(valRes.error)
  var skills = loadSkillRegistry(skillsPath)
  var found  = false
  for i in 0 ..< skills.len:
    if skills[i].name == name:
      skills[i].script      = scriptPath
      skills[i].permissions = permissions
      found = true; break
  if not found:
    skills.add(SkillManifest(name: name, script: scriptPath,
                             permissions: permissions))
  if fileExists(skillsPath): removeFile(skillsPath)
  for s in skills:
    let sr = saveSkillEntry(skillsPath, s)
    if sr.isErr:
      echo sr.error
      return err(sr.error)
  echo "Updated skill: " & name
  ok()

proc ctlSkillSearchRemote*(registry: string; query: string; limit = 10): Result[void, string] =
  let hits = searchRemoteSkills(registry, query, limit)
  if hits.isErr:
    echo "Error: " & hits.error
    return err(hits.error)
  if hits.value.len == 0:
    echo "(no results)"
    return ok()
  for hit in hits.value:
    let version = if hit.version.len > 0: " v" & hit.version else: ""
    let summary = if hit.summary.len > 0: "  " & hit.summary else: ""
    echo hit.slug & version & summary
  ok()

proc ctlSkillInstallRemote*(home, registry, slug: string): Result[void, string] =
  let origin = installRemoteSkill(home, registry, slug)
  if origin.isErr:
    echo "Error: " & origin.error
    return err(origin.error)
  echo "Installed " & origin.value.slug & "@" & origin.value.installedVersion
  ok()

proc ctlSkillUpdateRemote*(home, registry, slug: string): Result[void, string] =
  if slug.len > 0:
    let version = updateRemoteSkill(home, registry, slug)
    if version.isErr:
      echo "Error: " & version.error
      return err(version.error)
    echo "Updated " & slug & " -> " & version.value
    return ok()
  let lock = readRemoteSkillLockfile(home)
  if lock.skills.len == 0:
    echo "(no remote installs)"
    return ok()
  for installedSlug, _ in lock.skills.pairs:
    let version = updateRemoteSkill(home, registry, installedSlug)
    if version.isErr:
      echo "Error updating " & installedSlug & ": " & version.error
      return err(version.error)
    echo "Updated " & installedSlug & " -> " & version.value
  ok()
