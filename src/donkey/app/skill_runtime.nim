## skill_runtime — shared skill search/install/enable helpers for channels and native tools.

import std/[os, sequtils, strutils]
import results
import ../config/skills_registry
import ../config/clawhub_registry

type
  SkillSearchBackend* = proc(registry, query: string; limit: int):
      Result[seq[RemoteSkillSearchHit], string] {.gcsafe.}
  SkillInstallBackend* = proc(home, registry, slug: string):
      Result[RemoteSkillOrigin, string] {.gcsafe.}

func donkeyHomeDirFromPaddocks*(paddocksDir: string): string =
  parentDir(paddocksDir)

func donkeyHomeDirFromPaddock*(userPaddockDir: string): string =
  parentDir(parentDir(userPaddockDir))

func userSkillsPath*(userPaddockDir: string): string =
  userPaddockDir / "skills" / "skills.toml"

proc defaultSkillSearchBackend*(registry, query: string;
                                limit: int): Result[seq[RemoteSkillSearchHit], string] {.gcsafe.} =
  searchRemoteSkills(registry, query, limit)

proc defaultSkillInstallBackend*(home, registry, slug: string):
                                Result[RemoteSkillOrigin, string] {.gcsafe.} =
  installRemoteSkill(home, registry, slug)

proc writeSkillRegistry(path: string; skills: seq[SkillManifest]): Result[void, string] =
  if fileExists(path):
    removeFile(path)
  for skill in skills:
    let saved = saveSkillEntry(path, skill)
    if saved.isErr:
      return err(saved.error)
  ok()

proc upsertUserSkills(path: string; manifests: seq[SkillManifest]): Result[seq[SkillManifest], string] =
  var merged = loadSkillRegistry(path)
  for manifest in manifests:
    var found = false
    for idx in 0 ..< merged.len:
      if merged[idx].name == manifest.name:
        merged[idx] = manifest
        found = true
        break
    if not found:
      merged.add(manifest)
  let saved = writeSkillRegistry(path, merged)
  if saved.isErr:
    return err(saved.error)
  ok(merged)

proc removeUserSkill(path, name: string): Result[bool, string] =
  let skills = loadSkillRegistry(path)
  let kept = skills.filterIt(it.name != name)
  if kept.len == skills.len:
    return ok(false)
  let saved = writeSkillRegistry(path, kept)
  if saved.isErr:
    return err(saved.error)
  ok(true)

proc canonicalizeSkillManifest(skillDir: string;
                               manifest: SkillManifest;
                               version: string): SkillManifest =
  result = manifest
  if result.script.len > 0 and not isAbsolute(result.script):
    result.script = skillDir / result.script
  if result.version.len == 0:
    result.version = version

proc inferRemoteSkillManifest(skillDir, slug, version: string): Result[seq[SkillManifest], string] =
  const PreferredNames = ["main.ts", "index.ts", "skill.ts", "server.ts", "mcp.ts", "tool.ts",
                          "main.js", "index.js", "skill.js", "server.js", "mcp.js", "tool.js"]
  var candidates: seq[string] = @[]
  for path in walkDirRec(skillDir):
    if (DirSep & ClawhubDotDir & DirSep) in path:
      continue
    let ext = splitFile(path).ext.toLowerAscii()
    if ext notin [".ts", ".js", ".mjs", ".mts", ".cts"]:
      continue
    candidates.add(path)

  if candidates.len == 0:
    let hasSkillMd =
      fileExists(skillDir / "SKILL.md") or fileExists(skillDir / "skill.md")
    if hasSkillMd:
      return ok(@[SkillManifest(name: slug, version: version, script: "")])
    return err("Bundle remoto `" & slug & "` sem SKILL.md nem scripts Deno/JS — bundle corrupto ou registry retornou zip vazio.")

  var preferred: seq[string] = @[]
  for path in candidates:
    if path.extractFilename().toLowerAscii() in PreferredNames:
      preferred.add(path)

  let selected =
    if preferred.len == 1: preferred[0]
    elif candidates.len == 1: candidates[0]
    else: ""
  if selected.len == 0:
    return err(
      "O bundle remoto `" & slug & "` tem múltiplos scripts candidatos. " &
      "Adicione `skills.toml` ao bundle ou registre manualmente a skill desejada."
    )

  ok(@[SkillManifest(name: slug, version: version, script: selected)])

proc resolveRemoteSkillManifests(home, slug: string): Result[seq[SkillManifest], string] =
  let skillDir = remoteSkillDir(home, slug)
  if not dirExists(skillDir):
    return err("Skill remota não instalada: `" & slug & "`.")

  let origin = readRemoteSkillOrigin(skillDir).valueOr:
    return err(error)
  let version = if origin.installedVersion.len > 0: origin.installedVersion else: "0.1.0"

  let manifestPath = skillDir / "skills.toml"
  if fileExists(manifestPath):
    let manifests = loadSkillRegistry(manifestPath)
    if manifests.len == 0:
      return err("O bundle remoto `" & slug & "` tem `skills.toml` vazio.")
    var resolved: seq[SkillManifest] = @[]
    for manifest in manifests:
      resolved.add(canonicalizeSkillManifest(skillDir, manifest, version))
    return ok(resolved)

  inferRemoteSkillManifest(skillDir, slug, version)

func formatSkillManifestLine(manifest: SkillManifest): string =
  "- `" & manifest.name & "` v" & manifest.version & " — `" & manifest.script & "`"

func buildSkillHelpText*(): string =
  "Skills:\n" &
  "/skill list — mostra skills habilitadas para você e bundles remotos instalados\n" &
  "/skill search <query> — busca skills remotas no ClawHub\n" &
  "/skill install <slug> — baixa e habilita uma skill remota para você\n" &
  "/skill enable <slug> — habilita para você uma skill remota já instalada\n" &
  "/skill disable <name> — desabilita uma skill do seu runtime\n" &
  "/skill read <slug> — lê o SKILL.md de uma skill instalada"

proc buildSkillListText(userPaddockDir, home: string): string =
  let enabled = loadSkillRegistry(userSkillsPath(userPaddockDir))
  let installed = loadInstalledRemoteSkills(home)
  result = "Skills habilitadas para você:\n"
  if enabled.len == 0:
    result.add("(nenhuma)\n")
  else:
    for manifest in enabled:
      result.add(formatSkillManifestLine(manifest) & "\n")
  result.add("\nBundles remotos instalados:\n")
  if installed.len == 0:
    result.add("(nenhum)")
  else:
    for remote in installed:
      result.add("- `" & remote.slug & "` v" & remote.version & "\n")

proc buildSkillSearchText(hits: seq[RemoteSkillSearchHit]): string =
  result = "Resultados de skill:\n"
  if hits.len == 0:
    result.add("(nenhum resultado)")
    return
  for hit in hits:
    let version = if hit.version.len > 0: " v" & hit.version else: ""
    let summary = if hit.summary.len > 0: " — " & hit.summary else: ""
    result.add("- `" & hit.slug & "`" & version & summary & "\n")

proc enableRemoteSkillForUser(userPaddockDir, home, slug: string): Result[seq[SkillManifest], string] =
  let manifests = resolveRemoteSkillManifests(home, slug).valueOr:
    return err(error)
  let updated = upsertUserSkills(userSkillsPath(userPaddockDir), manifests).valueOr:
    return err(error)
  var enabled: seq[SkillManifest] = @[]
  for manifest in manifests:
    for existing in updated:
      if existing.name == manifest.name:
        enabled.add(existing)
        break
  ok(enabled)

proc applySkillCommand*(userPaddockDir: string;
                        value: string;
                        homeDir = "";
                        registry = "";
                        searchBackend: SkillSearchBackend = nil;
                        installBackend: SkillInstallBackend = nil): Result[string, string] =
  let home = if homeDir.len > 0: homeDir else: donkeyHomeDirFromPaddock(userPaddockDir)
  let registryUrl = if registry.len > 0: registry else: getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry)
  let searchFn = if searchBackend != nil: searchBackend else: defaultSkillSearchBackend
  let installFn = if installBackend != nil: installBackend else: defaultSkillInstallBackend
  let trimmed = value.strip
  if trimmed.len == 0 or trimmed.toLowerAscii() == "help":
    return ok(buildSkillHelpText())

  let parts = trimmed.splitWhitespace()
  if parts.len == 0:
    return ok(buildSkillHelpText())

  case parts[0].toLowerAscii()
  of "list":
    ok(buildSkillListText(userPaddockDir, home))
  of "search":
    if parts.len < 2:
      return err("Use `/skill search <query>`.")
    let hits = searchFn(registryUrl, parts[1 .. ^1].join(" "), 10).valueOr:
      return err(error)
    ok(buildSkillSearchText(hits))
  of "install":
    if parts.len != 2:
      return err("Use `/skill install <slug>`.")
    let slug = parts[1]
    if not dirExists(remoteSkillDir(home, slug)):
      discard installFn(home, registryUrl, slug).valueOr:
        return err(error)
    let manifests = resolveRemoteSkillManifests(home, slug).valueOr:
      return err(error)
    let hasExecutable = manifests.anyIt(it.script.len > 0)
    if hasExecutable:
      let enabled = enableRemoteSkillForUser(userPaddockDir, home, slug).valueOr:
        return err(error)
      ok(
        "✅ Skill remota instalada e habilitada: `" & slug & "`.\n" &
        enabled.map(formatSkillManifestLine).join("\n") &
        "\n\nEla entra no runtime na próxima mensagem sua."
      )
    else:
      ok(
        "✅ Skill `" & slug & "` instalada — é uma skill guidance-only (só SKILL.md, sem scripts).\n" &
        "Seu conteúdo já entra no system prompt automaticamente na próxima mensagem."
      )
  of "enable":
    if parts.len != 2:
      return err("Use `/skill enable <slug>`.")
    let slug = parts[1]
    let manifests = resolveRemoteSkillManifests(home, slug).valueOr:
      return err(error)
    let hasExecutable = manifests.anyIt(it.script.len > 0)
    if not hasExecutable:
      return ok("`" & slug & "` é uma skill guidance-only — não precisa de habilitação. " &
        "Ela já entra no system prompt automaticamente.")
    let enabled = enableRemoteSkillForUser(userPaddockDir, home, slug).valueOr:
      return err(error)
    ok(
      "✅ Skill habilitada: `" & slug & "`.\n" &
      enabled.map(formatSkillManifestLine).join("\n") &
      "\n\nEla entra no runtime na próxima mensagem sua."
    )
  of "disable", "remove":
    if parts.len != 2:
      return err("Use `/skill disable <name>`.")
    let removed = removeUserSkill(userSkillsPath(userPaddockDir), parts[1]).valueOr:
      return err(error)
    if removed:
      ok("✅ Skill desabilitada: `" & parts[1] & "`.")
    else:
      err("Skill não habilitada para você: `" & parts[1] & "`.")
  of "read":
    if parts.len != 2:
      return err("Use `/skill read <slug>`.")
    let slug = parts[1]
    let loaded = loadInstalledRemoteSkill(home, slug).valueOr:
      return err(error)
    ok(loaded.skillMd)
  else:
    err("Comando de skill inválido.\n\n" & buildSkillHelpText())
