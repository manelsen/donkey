## ctl_handler.nim — Dispatch all `donkey ctl` subcommands.
##
## Owns the cascading if/elif tree that was previously embedded in main().
## Each subcommand group (user, session, tool, skill, provider, memory, status)
## has its own handler proc; `dispatchCtl` routes to the right one.

import std/[os, strutils, tables]
import results
import core/types
import core/app_meta
import config/types
import config/tools_registry
import config/skills_registry
import config/clawhub_registry
import adapters/memory/md_file
import app/session_manager
import adapters/memory/multigraph_runtime
import ports/ipc
import ports/provider
import adapters/ipc/client as ipcClient
import domain/message

# ── ctl user commands ──────────────────────────────────────────────────────────

proc ctlUserList*(memory: MdFileAdapter) =
  if not dirExists(memory.paddocksDir):
    echo "(no paddocks directory — no users yet)"
    return
  var found = false
  for kind, name in walkDir(memory.paddocksDir):
    if kind == pcDir:
      found = true
      let userMdPath = name / "USER.md"
      if fileExists(userMdPath):
        echo name.extractFilename() & " (profile)"
      else:
        echo name.extractFilename() & " (no profile)"
  if not found:
    echo "(no users registered)"

proc ctlUserShow*(memory: MdFileAdapter; uuid: string) =
  let userId = UserId(uuid)
  if not memory.hasProfile(userId):
    echo "User not found: " & uuid
    quit(1)
  let ctx = memory.loadContext(userId)
  echo "=== USER.md ==="
  echo ctx.userMd
  if ctx.preferencesMd.len > 0:
    echo "=== PREFERENCES.md ==="
    echo ctx.preferencesMd
  if ctx.memoryMd.len > 0:
    echo "=== MEMORY.md (first 500 chars) ==="
    echo ctx.memoryMd[0 .. min(500, ctx.memoryMd.len - 1)]

proc ctlUserEdit*(memory: MdFileAdapter; uuid, field, value: string) =
  memory.updateUserField(UserId(uuid), field, value)
  echo "Updated " & uuid & ": " & field & " = " & value

proc ctlUserRevoke*(memory: MdFileAdapter; uuid: string; revoked: bool) =
  memory.updateUserField(UserId(uuid), "Access", if revoked: "revoked" else: "active")
  echo (if revoked: "Revoked " else: "Restored ") & uuid

# ── ctl session commands ───────────────────────────────────────────────────────

proc ctlSessionList*(sm: SessionManager; uuid: string) =
  ## Sessions are in-memory only; for an external CLI this shows nothing.
  let uid = UserId(uuid)
  var found = false
  for (userId, channels) in sm.listSessions():
    if userId == uid:
      found = true
      echo "Session for " & uuid & ":"
      for (kind, rawId) in channels:
        echo "  " & $kind & " : " & rawId
  if not found:
    echo "No active session for " & uuid

# ── ctl tool/skill commands ────────────────────────────────────────────────────

proc ctlToolInstall*(registryPath: string; command: string; args: seq[string]) =
  let entry = ToolEntry(kind: tkMcp, command: command, args: args)
  saveToolEntry(registryPath, entry)
  echo "Registered MCP server: " & command

proc ctlSkillInstall*(cfg: DonkeyConfig; skillsPath: string; name, scriptPath: string;
                      permissions: seq[string]) =
  discard validateSkillPermissions(permissions, cfg.webAllowlist).valueOr:
    echo error
    quit(1)
  let saveRes = saveSkillEntry(skillsPath, SkillManifest(
    name:        name,
    version:     "0.1.0",
    script:      scriptPath,
    permissions: permissions,
  ))
  if saveRes.isErr:
    echo saveRes.error
    quit(1)
  echo "Registered skill: " & name & " (" & scriptPath & ")"

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
                     permissions: seq[string]) =
  discard validateSkillPermissions(permissions, cfg.webAllowlist).valueOr:
    echo error
    quit(1)
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
      quit(1)
  echo "Updated skill: " & name

proc ctlSkillSearchRemote*(registry: string; query: string; limit = 10) =
  let hits = searchRemoteSkills(registry, query, limit).valueOr:
    echo "Error: " & error
    quit(1)
  if hits.len == 0:
    echo "(no results)"
    return
  for hit in hits:
    let version = if hit.version.len > 0: " v" & hit.version else: ""
    let summary = if hit.summary.len > 0: "  " & hit.summary else: ""
    echo hit.slug & version & summary

proc ctlSkillInstallRemote*(home, registry, slug: string) =
  let origin = installRemoteSkill(home, registry, slug).valueOr:
    echo "Error: " & error
    quit(1)
  echo "Installed " & origin.slug & "@" & origin.installedVersion

proc ctlSkillUpdateRemote*(home, registry, slug: string) =
  if slug.len > 0:
    let version = updateRemoteSkill(home, registry, slug).valueOr:
      echo "Error: " & error
      quit(1)
    echo "Updated " & slug & " -> " & version
    return
  let lock = readRemoteSkillLockfile(home)
  if lock.skills.len == 0:
    echo "(no remote installs)"
    return
  for installedSlug, _ in lock.skills.pairs:
    let version = updateRemoteSkill(home, registry, installedSlug).valueOr:
      echo "Error updating " & installedSlug & ": " & error
      quit(1)
    echo "Updated " & installedSlug & " -> " & version

# ── ctl provider test ──────────────────────────────────────────────────────────

proc ctlProviderTest*(name: string;
                      buildCompleteFnRef: proc(preferencesMd: string): CompleteFn {.gcsafe.}) {.gcsafe.} =
  let fn = buildCompleteFnRef("provider = \"" & name & "\"")
  var h = message.newHistory()
  h.addUser("ping")
  let req  = message.buildPrompt("Reply with one word: pong", h, "")
  let resp = fn(req)
  if resp.isOk:
    echo "OK — " & name & " responded: " & resp.value.text
  else:
    echo "FAIL — " & name & ": " & resp.error
    quit(1)

# ── ctl memory commands ────────────────────────────────────────────────────────
## Delegated to multigraph_runtime (already has correct MAGMA-aware impls).

# ── ctl status ─────────────────────────────────────────────────────────────────

proc ctlStatus*(cfg: DonkeyConfig) =
  let sockPath = cfg.home / SockFileName
  let sr = ipcClient.queryStatus(sockPath)
  if sr.isErr:
    echo "Error: " & sr.error; quit(1)
  let st = sr.value
  echo formatDaemonStatus(st)

# ── dispatch ───────────────────────────────────────────────────────────────────

proc dispatchCtl*(cfg: DonkeyConfig;
                  memory: MdFileAdapter;
                  registryPath: string;
                  args: seq[string];
                  buildCompleteFnRef: proc(preferencesMd: string): CompleteFn {.gcsafe.}): int {.gcsafe.} =
  ## Routes ctl subcommands. Returns exit code (0=ok, 1=error, 2=unrecognized).
  if args.len < 2: return 2  # unrecognized — show help in caller

  # ── user ──
  if args[1] == "user" and args.len >= 3 and args[2] == "list":
    ctlUserList(memory); return 0
  if args[1] == "user" and args.len >= 4 and args[2] == "show":
    ctlUserShow(memory, args[3]); return 0
  if args[1] == "user" and args.len >= 6 and args[2] == "edit":
    ctlUserEdit(memory, args[3], args[4], args[5 .. ^1].join(" ")); return 0
  if args[1] == "user" and args.len >= 4 and args[2] == "revoke":
    ctlUserRevoke(memory, args[3], true); return 0
  if args[1] == "user" and args.len >= 4 and args[2] == "allow":
    ctlUserRevoke(memory, args[3], false); return 0

  # ── session ──
  if args[1] == "session" and args.len >= 4 and args[2] == "list":
    var sm: SessionManager
    sm.init()
    ctlSessionList(sm, args[3]); return 0

  # ── tool ──
  if args[1] == "tool" and args.len >= 4 and args[2] == "install":
    ctlToolInstall(registryPath, args[3], args[4 ..^ 1]); return 0

  # ── skill ──
  let skillsPath = cfg.home / "skills.toml"
  if args[1] == "skill" and args[2] == "install" and args.len >= 5:
    ctlSkillInstall(cfg, skillsPath, args[3], args[4], args[5 ..^ 1]); return 0
  if args[1] == "skill" and args[2] == "install" and args.len == 4:
    ## Remote install (slug only)
    ctlSkillInstallRemote(cfg.home,
                          getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry),
                          args[3]); return 0
  if args[1] == "skill" and args[2] == "search" and args.len >= 4:
    ctlSkillSearchRemote(getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry), args[3]); return 0
  if args[1] == "skill" and args[2] == "list" and args.len >= 3:
    ctlSkillList(skillsPath); return 0
  if args[1] == "skill" and args[2] == "update" and args.len >= 5:
    ctlSkillUpdate(cfg, skillsPath, args[3], args[4], args[5 ..^ 1]); return 0
  if args[1] == "skill" and args[2] == "update" and args.len >= 3:
    let slug = if args.len >= 4: args[3] else: ""
    ctlSkillUpdateRemote(cfg.home,
                         getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry),
                         slug); return 0

  # ── provider ──
  if args[1] == "provider" and args.len >= 4 and args[2] == "test":
    ctlProviderTest(args[3], buildCompleteFnRef); return 0

  # ── memory ──
  when defined(withPostgres) or defined(withSqlite):
    proc makeMagmaMemory(): MdFileAdapter =
      MdFileAdapter(
        paddocksDir: cfg.paddocks,
        magmaDsn: getEnv("DONKEY_PG_DSN"),
        magmaSqlitePath:
          block:
            let p = getEnv("DONKEY_MAGMA_SQLITE_PATH")
            if p.len > 0: p else: cfg.home / "state" / "magma.sqlite",
        magmaSqliteVectorPath:
          block:
            let vecPath = getEnv("DONKEY_SQLITE_VEC_PATH")
            if vecPath.len > 0: vecPath else: getEnv("DONKEY_SQLITE_VECTOR_PATH"),
      )

    if args[1] == "memory" and args[2] == "search" and args.len >= 5:
      ctlMemorySearch(makeMagmaMemory(), args[3], args[4]); return 0
    if args[1] == "memory" and args[2] == "import" and args.len >= 4:
      ctlMemoryImport(makeMagmaMemory(), args[3]); return 0
    if args[1] == "memory" and args[2] == "export" and args.len >= 4:
      let outDir = if args.len >= 5: args[4] else: ""
      ctlMemoryExport(makeMagmaMemory(), args[3], outDir); return 0
  else:
    if args[1] == "memory" and args[2] in ["search", "import", "export"]:
      echo "This build disabled MAGMA support; rebuild with -d:withPostgres or -d:withSqlite"
      return 1

  # ── status ──
  if args[1] == "status" and args.len >= 2:
    ctlStatus(cfg); return 0

  # ── unrecognized ──
  2
