## ctl_handler.nim — Dispatch all `donkey ctl` subcommands.
##
## Owns the cascading if/elif tree that was previously embedded in main().
## Each subcommand group (user, session, tool, skill, provider, memory, status)
## has its own handler proc; `dispatchCtl` routes to the right one.

import std/[algorithm, options, os, sets, strutils, tables, terminal, times]
import core/types
import core/pipeops
import core/app_meta
import config/types
import config/tools_registry
import adapters/tool/mcp_oauth
import config/environment
import domain/memory/conversation_search_pure
import domain/turn_trace_pure
import app/turn_traces
import config/skills_registry
import config/clawhub_registry
import config/dotenv
import config/loader
import adapters/memory/md_file
import adapters/state/pairing_store
import admin_ops
import adapters/state/approval_store
import adapters/state/standing_approvals
import ports/approval
import adapters/secrets/vault
import app/session_manager
import app/tools/memory_ingest_io
import adapters/memory/multigraph_runtime
import ports/ipc
import ports/provider
import adapters/ipc/client as ipcClient
import adapters/filesystem/fs_adapter
import domain/message
import domain/automation/schedule_pure
import domain/automation/schedule_view
import adapters/state/schedule_store

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

proc ctlUserShow*(memory: MdFileAdapter; uuid: string): Result[void, string] =
  let userId = UserId(uuid)
  if not memory.hasProfile(userId):
    return err("User not found: " & uuid)
  let ctx = memory.loadContext(userId)
  echo "=== USER.md ==="
  echo ctx.userMd
  if ctx.preferencesMd.len > 0:
    echo "=== PREFERENCES.md ==="
    echo ctx.preferencesMd
  if ctx.memoryMd.len > 0:
    echo "=== MEMORY.md (first 500 chars) ==="
    echo ctx.memoryMd[0 .. min(500, ctx.memoryMd.len - 1)]
  ok()

proc ctlUserEdit*(memory: MdFileAdapter;
                  uuid, field, value: string): Result[void, string] =
  ## An edit that was not saved is an error, so the command exits non-zero.
  ? memory.updateUserField(UserId(uuid), field, value)
  echo "Updated " & uuid & ": " & field & " = " & value
  ok()

proc ctlUserRevoke*(memory: MdFileAdapter; uuid: string; revoked: bool): Result[void, string] =
  let done = setUserAccess(memory, uuid, revoked)
  if done.isErr:
    echo "Error: " & done.error
    return err(done.error)
  echo done.get
  ok()

# ── ctl pairing commands ───────────────────────────────────────────────────────

proc ctlPairList*(store: PairingStore): Result[void, string] =
  let loaded = store.load()
  if loaded.isErr:
    return err(loaded.error)
  let requests = loaded.get()
  if requests.len == 0:
    echo "No pending pairing requests."
    return ok()
  echo "code\tchannel\trawId\texpires_in"
  for request in requests:
    let remaining = int(max(0.0, request.expiresAt - epochTime()))
    echo request.code & "\t" & $request.channel & "\t" &
         request.rawId & "\t" & $remaining & "s"
  ok()

proc ctlPairApprove*(cfg: DonkeyConfig; memory: MdFileAdapter;
                     store: PairingStore; code: string): Result[void, string] =
  let done = ? approvePairing(cfg, memory, store, code)
  echo done
  ok()

proc ctlPairReject*(store: PairingStore; code: string): Result[void, string] =
  let done = ? rejectPairing(store, code)
  echo done
  ok()

# ── ctl approval commands ──────────────────────────────────────────────────────

proc ctlStandingApprovals*(standing: StandingApprovalPort; args: seq[string]): Result[void, string] =
  ## `approval standing list <user>` and `approval standing revoke <user> <key>`:
  ## the approvals a person made stand with "always" (MCP sampling, E5.2).
  if args.len >= 2 and args[0] == "list":
    let keys = standing.list(args[1])
    if keys.len == 0:
      echo "No standing approvals for " & args[1] & "."
    for k in keys:
      echo k
    return ok()
  if args.len >= 3 and args[0] == "revoke":
    ? standing.revoke(args[1], args[2])
    echo "Revoked " & args[2] & " for " & args[1] & "."
    return ok()
  err("usage: approval standing list <user> | approval standing revoke <user> <key>")

proc ctlApprovalList*(store: ApprovalStore; userId = ""): Result[void, string] =
  let pending = store.listPending(userId)
  if pending.isErr:
    return err(pending.error)
  if pending.get().len == 0:
    echo "No pending approvals."
    return ok()
  echo "id\tuser\ttool\tsummary\texpires_in"
  for request in pending.get():
    let remaining = int(max(0'i64, request.expiresAtMs - epochMs()) div 1000)
    echo request.id & "\t" & request.userId & "\t" & request.toolName & "\t" &
         request.summary & "\t" & $remaining & "s"
  ok()

proc ctlApprovalDecide*(store: ApprovalStore; id: string;
                        approved: bool): Result[void, string] =
  let res = store.decide(id, "", approved, admin = true)
  if res.isErr:
    return err(res.error)
  echo (if approved: "Approved " else: "Denied ") & id
  ok()

# ── ctl secret commands ──────────────────────────────────────────────────────

proc ctlSecretSet*(vault: SecretVault; name: string): Result[void, string] =
  ## Reads one line from stdin without echo so the secret never appears in
  ## shell history or the process argument list.
  stderr.writeLine "Enter value for " & name & ":"
  var secret = ""
  try:
    secret = readPasswordFromStdin("")
  except CatchableError as e:
    return err("could not read secret from stdin: " & e.msg)
  let res = vault.setSecret(name, secret)
  if res.isErr:
    return err(res.error)
  echo "Stored secret " & name & "."
  ok()

proc ctlSecretList*(vault: SecretVault): Result[void, string] =
  let names = vault.listSecretNames()
  if names.isErr:
    return err(names.error)
  if names.get().len == 0:
    echo "No secrets stored."
    return ok()
  for name in names.get():
    echo name
  ok()

proc ctlSecretRemove*(vault: SecretVault; name: string): Result[void, string] =
  let res = vault.removeSecret(name)
  if res.isErr:
    return err(res.error)
  if not res.get():
    return err("secret not found: " & name)
  echo "Removed secret " & name & "."
  ok()

proc ctlSecretImportEnv*(vault: SecretVault;
                         path: string): Result[void, string] =
  if not fileExists(path):
    return err("env file not found: " & path)
  var entries: seq[(string, string)]
  try:
    entries = parseEnvFile(path)
  except CatchableError as e:
    return err("could not read " & path & ": " & e.msg)
  var prepared: seq[(string, string)]
  var seen = initHashSet[string]()
  var skipped: seq[string]
  for (name, value) in entries:
    ## loadEnvFile keeps the first occurrence; import must do the same.
    if value.len == 0 or name in seen:
      continue
    seen.incl(name)
    if name in BootstrapEnvVars:
      skipped.add(name)
      continue
    prepared.add((name, value))

  let imported = vault.setSecrets(prepared)
  if imported.isErr:
    return err("could not import " & path & ": " & imported.error)
  for name in skipped:
    echo "Skipped bootstrap variable " & name & " (keep it in donkey.env)."
  echo "Imported " & $imported.get() & " secret(s) from " & path & "."
  ok()

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

const McpOAuthRedirect* = "http://127.0.0.1:8976/callback"
  ## Nothing listens there: the browser fails to load it, and the operator
  ## copies the URL (with the code) from the address bar back into the CLI.

type McpLoginArgs* = object
  clientId*:  string   ## pre-registered client; "" = dynamic registration
  secretEnv*: string   ## the variable holding its secret; "" = public client

func parseMcpLoginArgs*(args: seq[string]): Result[McpLoginArgs, string] =
  ## `[--client-id ID [--client-secret-env NAME]]`
  var parsed = McpLoginArgs()
  var i = 0
  while i < args.len:
    case args[i]
    of "--client-id", "--client-secret-env":
      if i + 1 >= args.len or args[i + 1].len == 0:
        return err(args[i] & " needs a value")
      if args[i] == "--client-id": parsed.clientId = args[i + 1]
      else: parsed.secretEnv = args[i + 1]
      i += 2
    else:
      return err("unknown option: " & args[i])
  if parsed.secretEnv.len > 0 and parsed.clientId.len == 0:
    return err("--client-secret-env needs --client-id")
  ok(parsed)

func preregisteredFrom*(args: McpLoginArgs; env: Environment): Result[PreregisteredClient, string] =
  ## The client to log in with; its secret read by name from the
  ## environment snapshot (donkey.env or the vault), never from the command
  ## line.
  var secret = ""
  if args.secretEnv.len > 0:
    secret = env.get(args.secretEnv)
    if secret.len == 0:
      return err(args.secretEnv & " is not set; put the client secret there " &
                 "(`donkey ctl secret set " & args.secretEnv & "`)")
  ok(PreregisteredClient(clientId: args.clientId, secret: secret,
                         secretEnv: args.secretEnv))

proc ctlMcpLogin*(home, url: string; env = Environment();
                  args: seq[string] = @[]): int =
  ## `ctl mcp login <url> [--client-id ID [--client-secret-env NAME]]`:
  ## OAuth for a remote MCP server, browser-less.
  let options = parseMcpLoginArgs(args)
  if options.isErr:
    echo options.error
    echo "usage: donkey ctl mcp login <url> [--client-id ID [--client-secret-env NAME]]"
    return 1
  let client = preregisteredFrom(options.get, env)
  if client.isErr:
    echo client.error
    return 1
  let http = productionOAuthPort()
  let pending = beginMcpLogin(url, McpOAuthRedirect, http, client.get)
  if pending.isErr:
    echo pending.error
    return 1
  echo "Open this URL in a browser and authorize " & AppName & ":"
  echo ""
  echo "  " & pending.get.authorizationUrl
  echo ""
  echo "The browser then goes to " & McpOAuthRedirect & " and shows an error page;"
  echo "that is expected. Copy the full URL from the address bar and paste it here:"
  stdout.write("> ")
  stdout.flushFile()
  let pasted = try: stdin.readLine() except IOError: ""
  let rec = completeMcpLogin(pending.get, pasted, http, getTime().toUnix)
  if rec.isErr:
    echo rec.error
    return 1
  let saved = saveMcpOAuth(home / "state" / McpOAuthDirName, rec.get)
  if saved.isErr:
    echo "could not store the tokens: " & saved.error
    return 1
  echo "Logged in to " & url & "."
  0

type TraceArgs* = object
  sinceMs*: int64
  user*:    string

func parseTraceArgs*(args: seq[string]; nowMs: int64): Result[TraceArgs, string] =
  ## `[--since 7d|24h|2w|YYYY-MM-DD] [--user UUID]`
  var parsed = TraceArgs()
  var i = 0
  while i < args.len:
    if i + 1 >= args.len or args[i] notin ["--since", "--user"]:
      return err("unknown or incomplete option: " & args[i])
    if args[i] == "--since":
      parsed.sinceMs = ? parseTimeBound(args[i + 1], nowMs, isUntil = false)
    else:
      parsed.user = args[i + 1]
    i += 2
  ok(parsed)

proc exportTraces*(dir: string; sinceMs: int64; user: string): seq[string] =
  ## The trace lines in `dir` (`tracesDir(paddocks)`), oldest day first.
  var files: seq[string]
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".jsonl"):
      files.add path
  files.sort()
  for path in files:
    let text = try: readFile(path) except IOError: ""
    for line in text.splitLines:
      if line.strip.len > 0 and traceMatches(line, sinceMs, user):
        result.add line

proc ctlTraces*(paddocksDir: string; args: seq[string]): int =
  ## `ctl traces [--since …] [--user UUID]`: per-turn traces as JSON lines
  ## (written when DONKEY_TRACES is on), for export.
  let options = parseTraceArgs(args, getTime().toUnix * 1000)
  if options.isErr:
    echo options.error
    echo "usage: donkey ctl traces [--since 7d|24h|YYYY-MM-DD] [--user UUID]"
    return 1
  for line in exportTraces(tracesDir(paddocksDir), options.get.sinceMs, options.get.user):
    echo line
  0

proc ctlToolAddHttp*(home, registryPath: string; args: seq[string]): int =
  ## `ctl tool add-http <url> [--token-env NAME | --oauth]`: a remote MCP
  ## server over Streamable HTTP. Only the variable name is stored, never the
  ## token; `--oauth` logs in right away.
  if args.len == 0:
    echo "usage: donkey ctl tool add-http <url> [--token-env NAME | --oauth]"
    return 1
  let url = args[0]
  var tokenEnv = ""
  var oauth = false
  var i = 1
  while i < args.len:
    if args[i] == "--token-env" and i + 1 < args.len:
      tokenEnv = args[i + 1]
      i += 2
    elif args[i] == "--oauth":
      oauth = true
      inc i
    else:
      echo "unknown option: " & args[i]
      return 1
  if oauth and tokenEnv.len > 0:
    echo "--oauth and --token-env are exclusive"
    return 1
  let valid = validMcpHttpUrl(url)
  if valid.isErr:
    echo valid.error
    return 1
  saveToolEntry(registryPath, ToolEntry(kind: tkMcpHttp, url: url,
                                        tokenEnv: tokenEnv, oauth: oauth))
  echo "Registered MCP server (HTTP): " & url &
    (if tokenEnv.len > 0: " — bearer from $" & tokenEnv
     elif oauth: " — OAuth" else: "")
  if oauth:
    return ctlMcpLogin(home, url)
  0

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

# ── ctl provider test ──────────────────────────────────────────────────────────

proc ctlProviderTest*(name: string;
                      buildCompleteFnRef: proc(preferencesMd: string): CompleteFn): Result[void, string] =
  let fn = buildCompleteFnRef("provider = \"" & name & "\"")
  var h = message.newHistory()
  h.addUser("ping")
  let req  = message.buildPrompt("Reply with one word: pong", h, "")
  let resp = fn(req)
  if resp.isOk:
    echo "OK — " & name & " responded: " & resp.value.text
    ok()
  else:
    echo "FAIL — " & name & ": " & resp.error
    err(resp.error)

# ── ctl memory commands ────────────────────────────────────────────────────────
## Delegated to multigraph_runtime (already has correct MAGMA-aware impls).

# ── ctl status ─────────────────────────────────────────────────────────────────

proc ctlStatus*(cfg: DonkeyConfig): Result[void, string] =
  let sockPath = cfg.home / SockFileName
  let sr = ipcClient.queryStatus(sockPath)
  if sr.isErr:
    return err(sr.error)
  let st = sr.value
  echo formatDaemonStatus(st)
  ok()

# ── ctl schedule commands ──────────────────────────────────────────────────────
## `schedule list/show` are read-only and work with the daemon stopped: they
## open `{home}/state/schedules.json` through the same store the daemon uses.
##
## The handlers below return the rendered stdout text as the `Result` value
## (instead of echoing it) so the output is testable without capturing stdout;
## `dispatchSchedule` is the only caller and prints it. That is a deliberate
## small deviation from the `Result[void, string]` + echo convention used by
## the older ctl groups.

const
  ScheduleDefaultChannel = "telegram"
  ScheduleDefaultTz = "UTC+00:00"
  ScheduleDefaultCatchUp = "skip"

proc scheduleNow(nowMs: int64): int64 =
  ## `-1` means "use the wall clock"; tests always inject an instant.
  if nowMs >= 0: nowMs else: epochMs()


func parseCatchUpArg(raw: string): Result[ScheduleCatchUp, string] =
  case raw.strip().toLowerAscii()
  of "", "skip": ok(scSkip)
  of "once": ok(scOnce)
  else:
    err("invalid catch-up policy '" & raw & "': expected skip or once")

proc ctlScheduleList*(stateDir: string; asJson = false;
                      nowMs = -1'i64): Result[string, string] =
  ## `list`: every schedule, never the payload. Empty store prints
  ## `No schedules.` (human) or `[]` (`--json`) and is a success.
  let loaded = newScheduleStoreRef(stateDir).loadAllRecords()
  if loaded.isErr:
    return err(loaded.error)
  var rows: seq[ScheduleViewRecord]
  for record in loaded.get():
    rows.add record.toViewRecord
  let at = scheduleNow(nowMs)
  if asJson:
    return ok(formatScheduleJson(rows, at))
  ok(schedulePanelLines(rows, at).join("\n"))

proc ctlScheduleShow*(stateDir, scheduleId: string; asJson = false;
                      nowMs = -1'i64): Result[string, string] =
  ## `show <id>`: detail for one schedule, including the payload. Unknown id
  ## is an error (the caller exits non-zero).
  let loaded = newScheduleStoreRef(stateDir).loadRecord(scheduleId)
  if loaded.isErr:
    return err(loaded.error)
  if loaded.get().isNone:
    return err("schedule not found: " & scheduleId)
  let record = loaded.get().get()
  let row = record.toViewRecord
  let at = scheduleNow(nowMs)
  if asJson:
    return ok(formatScheduleObjectJson(row, at))
  var lines = scheduleDetailLines(row, at)
  if record.loadWarning.len > 0:
    lines.insert("warning: " & record.loadWarning, 0)
  ok(lines.join("\n"))

proc ctlScheduleAdd*(stateDir, scheduleId, cronExpr, userId, payload: string;
                     nowMs: int64; channel = ScheduleDefaultChannel;
                     tz = ScheduleDefaultTz;
                     catchUp = ScheduleDefaultCatchUp): Result[string, string] =
  ## `add <id> ...`: validate, refuse a duplicate id before touching the file,
  ## then persist `createdAtMs = now`, `lastRunAtMs = createdAtMs` (creation
  ## never fires) and `lastFireAtMs = 0`.
  let id = scheduleId.strip()
  let offset = parseTzOffset(tz)
  if offset.isErr:
    return err(offset.error)
  let policy = parseCatchUpArg(catchUp)
  if policy.isErr:
    return err(policy.error)

  let spec = ScheduleSpec(
    id: id,
    cronExpr: cronExpr,
    tzOffsetMinutes: offset.get(),
    userId: userId,
    channel: channel,
    payload: payload,
    catchUp: policy.get(),
    enabled: true,
    createdAtMs: nowMs,
  )
  let valid = validateScheduleSpec(spec)
  if valid.isErr:
    return err(valid.error)

  let store = newScheduleStoreRef(stateDir)
  let record = ScheduleRecord(
    spec: spec,
    lastRunAtMs: spec.createdAtMs,
    lastFireAtMs: 0,
  )
  ## Check-and-insert in one store transaction: `loadRecord` + `upsert` in two
  ## lock acquisitions let two concurrent `add`s both pass the duplicate check.
  let inserted = store.insertIfAbsent(record)
  if inserted.isErr:
    return err(inserted.error)
  if not inserted.get():
    return err("schedule '" & spec.id & "' already exists; remove it first " &
               "with `donkey ctl schedule remove " & spec.id & "`")
  ok("Added schedule '" & spec.id & "' (" & spec.cronExpr & ", " &
     formatTzOffset(spec.tzOffsetMinutes) & ", " & spec.channel & ")")

proc ctlScheduleRemove*(stateDir, scheduleId: string
                       ): Result[string, string] =
  ## `remove <id>`: unknown id is an error.
  let store = newScheduleStoreRef(stateDir)
  let existing = store.loadRecord(scheduleId)
  if existing.isErr:
    return err(existing.error)
  if existing.get().isNone:
    return err("schedule not found: " & scheduleId)
  let removed = store.remove(scheduleId)
  if removed.isErr:
    return err(removed.error)
  ok("Removed schedule '" & scheduleId & "'.")

proc ctlScheduleSetEnabled*(stateDir, scheduleId: string; enabled: bool;
                            nowMs = -1'i64): Result[string, string] =
  ## `enable`/`disable <id>`: one store transaction flips `spec.enabled`.
  ##
  ## A real re-enable (disabled → enabled) also writes `lastRunAtMs = now`:
  ## if the daemon was stopped for the whole disabled period, no tick advanced
  ## the watermark, and the first tick after enabling would catch up on that
  ## window. `lastFireAtMs` is historical and stays untouched. Unknown id is
  ## an error.
  let toggled = newScheduleStoreRef(stateDir).setEnabled(
    scheduleId, enabled, scheduleNow(nowMs))
  if toggled.isErr:
    return err(toggled.error)
  if not toggled.get():
    return err("schedule not found: " & scheduleId)
  ok((if enabled: "Enabled schedule '" else: "Disabled schedule '") &
     scheduleId & "'.")

proc scheduleFlagValue*(args: seq[string]; name: string): Option[string] =
  var i = 0
  while i < args.len:
    if args[i] == name:
      if i + 1 < args.len:
        return some(args[i + 1])
      return none(string)
    if args[i].startsWith(name & "="):
      return some(args[i][name.len + 1 .. ^1])
    inc i
  none(string)

const ScheduleValueFlags = ["--cron", "--user", "--payload", "--channel",
                            "--tz", "--catchup", "--catch-up"]

func scheduleAddId*(raw: openArray[string]; fallback: seq[string]): string =
  ## The schedule id is the first positional after `add`. `main()` parses with
  ## `std/parseopt`, whose `cmdArgument` also yields the *value* of a long
  ## option, so `args[3]` can be the cron expression when flags come first —
  ## and `add --cron "0 9 * * *" ... daily` would create a schedule whose id is
  ## the cron. Walk the raw argv instead, skipping flags and their values.
  var i = 0
  while i < raw.len and raw[i] != "add":
    inc i
  if i >= raw.len:
    if fallback.len >= 4 and not fallback[3].startsWith("--"):
      return fallback[3]
    return ""
  inc i
  while i < raw.len:
    let token = raw[i]
    if token.startsWith("--"):
      inc i
      if '=' notin token and token in ScheduleValueFlags and i < raw.len:
        inc i
      continue
    return token
  ""

func scheduleHasFlag(args: seq[string]; name: string): bool =
  for arg in args:
    if arg == name:
      return true
  false

proc scheduleUsage() =
  echo "Usage: donkey ctl schedule <list|show|add|remove|enable|disable> [args]"
  echo ""
  echo "  list [--json]"
  echo "  show <id> [--json]"
  echo "  add <id> --cron <expr> --user <id> --payload <text>"
  echo "           [--channel " & ScheduleDefaultChannel & "] [--tz UTC+00:00] [--catchup skip|once]"
  echo "           <expr>: 5-field cron (\"0 9 * * 1-5\"), @hourly, @daily, @weekly,"
  echo "           @monthly, @yearly, or \"@every 30m\" (m/h/d, counted from creation)"
  echo "  remove <id>"
  echo "  enable <id>"
  echo "  disable <id>"

proc dispatchSchedule(stateDir: string; args: seq[string];
                      flagArgs: seq[string] = @[]): int =
  ## `args[1] == "schedule"`; `args[2]` is the subcommand.
  ##
  ## `flagArgs` defaults to the raw `commandLineParams()`: `main()` parses
  ## argv with `std/getopt`, which swallows every `--flag` before the command
  ## registry sees it (`else: discard`), so `args` only carries positionals.
  ## Reading the raw argv here is the smallest fix that keeps `src/donkey.nim`
  ## out of this story; tests can inject `flagArgs` explicitly.
  let rawFlags = if flagArgs.len > 0: flagArgs else: commandLineParams()
  let sub = if args.len >= 3: args[2] else: ""
  let asJson = scheduleHasFlag(rawFlags, "--json")
  if sub == "list":
    let r = ctlScheduleList(stateDir, asJson, epochMs())
    if r.isErr: echo "Error: " & r.error; return 1
    echo r.get()
    return 0

  if sub == "show":
    if args.len < 4 or args[3].startsWith("--"):
      echo "Error: missing schedule id"
      return 1
    let r = ctlScheduleShow(stateDir, args[3], asJson, epochMs())
    if r.isErr: echo "Error: " & r.error; return 1
    echo r.get()
    return 0

  if sub == "add":
    let id = scheduleAddId(rawFlags, args)
    if id.len == 0 or id.startsWith("--"):
      echo "Error: missing schedule id"
      return 1
    let cron = scheduleFlagValue(rawFlags, "--cron")
    let user = scheduleFlagValue(rawFlags, "--user")
    let payload = scheduleFlagValue(rawFlags, "--payload")
    if cron.isNone:
      echo "Error: --cron is required"
      return 1
    if user.isNone:
      echo "Error: --user is required"
      return 1
    if payload.isNone:
      echo "Error: --payload is required"
      return 1
    let channel = scheduleFlagValue(rawFlags, "--channel")
      .get(ScheduleDefaultChannel)
    let tz = scheduleFlagValue(rawFlags, "--tz").get(ScheduleDefaultTz)
    let catchUp = scheduleFlagValue(rawFlags, "--catchup")
      .get(scheduleFlagValue(rawFlags, "--catch-up").get(ScheduleDefaultCatchUp))
    let r = ctlScheduleAdd(stateDir, id, cron.get(), user.get(),
                           payload.get(), epochMs(), channel = channel, tz = tz,
                           catchUp = catchUp)
    if r.isErr: echo "Error: " & r.error; return 1
    echo r.get()
    return 0

  if sub in ["remove", "enable", "disable"]:
    if args.len < 4 or args[3].startsWith("--"):
      echo "Error: missing schedule id"
      return 1
    let r =
      if sub == "remove": ctlScheduleRemove(stateDir, args[3])
      else: ctlScheduleSetEnabled(stateDir, args[3], sub == "enable")
    if r.isErr: echo "Error: " & r.error; return 1
    echo r.get()
    return 0

  scheduleUsage()
  2

# ── dispatch ───────────────────────────────────────────────────────────────────

proc dispatchCtl*(cfg: DonkeyConfig;
                  memory: MdFileAdapter;
                  registryPath: string;
                  args: seq[string];
                  buildCompleteFnRef: proc(preferencesMd: string): CompleteFn): int =
  ## Routes ctl subcommands. Returns exit code (0=ok, 1=error, 2=unrecognized).
  if args.len < 2: return 2  # unrecognized — show help in caller

  # ── user ──
  if args[1] == "user" and args.len >= 3 and args[2] == "list":
    ctlUserList(memory); return 0
  if args[1] == "user" and args.len >= 4 and args[2] == "show":
    let r = ctlUserShow(memory, args[3])
    if r.isErr: echo r.error; return 1
    return 0
  if args[1] == "user" and args.len >= 6 and args[2] == "edit":
    let res = ctlUserEdit(memory, args[3], args[4], args[5 .. ^1].join(" "))
    if res.isErr: echo "Error: " & res.error; return 1
    return 0
  if args[1] == "user" and args.len >= 4 and args[2] == "revoke":
    let res = ctlUserRevoke(memory, args[3], true)
    if res.isErr: echo res.error; return 1
    return 0
  if args[1] == "user" and args.len >= 4 and args[2] == "allow":
    let res = ctlUserRevoke(memory, args[3], false)
    if res.isErr: echo res.error; return 1
    return 0

  # ── pairing ──
  let pairingStore = newPairingStore(cfg.home / "state" / "pairings.json")
  if args[1] == "pair" and args.len >= 3 and args[2] == "list":
    let res = ctlPairList(pairingStore)
    if res.isErr: echo res.error; return 1
    return 0
  if args[1] == "pair" and args.len >= 4 and args[2] == "approve":
    let res = ctlPairApprove(cfg, memory, pairingStore, args[3])
    if res.isErr: echo res.error; return 1
    return 0
  if args[1] == "pair" and args.len >= 4 and args[2] == "reject":
    let res = ctlPairReject(pairingStore, args[3])
    if res.isErr: echo res.error; return 1
    return 0

  # ── approval ──
  let approvalStore = newApprovalStore(cfg.home / "state" / "approvals.json")
  if args[1] == "approval" and args.len >= 3 and args[2] == "standing":
    let standing = newStandingApprovals(cfg.home / "state" / StandingApprovalsFile).toStandingPort()
    let res = ctlStandingApprovals(standing, args[3 .. ^1])
    if res.isErr: echo res.error; return 1
    return 0
  if args[1] == "approval" and args.len >= 3 and args[2] == "list":
    let res = ctlApprovalList(approvalStore, if args.len >= 4: args[3] else: "")
    if res.isErr: echo res.error; return 1
    return 0
  if args[1] == "approval" and args.len >= 4 and args[2] == "approve":
    let res = ctlApprovalDecide(approvalStore, args[3], true)
    if res.isErr: echo res.error; return 1
    return 0
  if args[1] == "approval" and args.len >= 4 and args[2] == "deny":
    let res = ctlApprovalDecide(approvalStore, args[3], false)
    if res.isErr: echo res.error; return 1
    return 0

  # ── secret ──
  let secretVault = newSecretVault(cfg.home)
  if args[1] == "secret" and args.len >= 3 and args[2] == "list":
    let res = ctlSecretList(secretVault)
    if res.isErr: echo res.error; return 1
    return 0
  if args[1] == "secret" and args.len >= 4 and args[2] == "set":
    if args.len > 4:
      echo "Error: pass the secret on stdin, not as a command-line argument."
      return 1
    let res = ctlSecretSet(secretVault, args[3])
    if res.isErr: echo res.error; return 1
    return 0
  if args[1] == "secret" and args.len >= 4 and args[2] == "remove":
    let res = ctlSecretRemove(secretVault, args[3])
    if res.isErr: echo res.error; return 1
    return 0
  if args[1] == "secret" and args.len >= 3 and args[2] == "import-env":
    let path = if args.len >= 4: args[3] else: envFilePath(resolveHome(cfg.env))
    let res = ctlSecretImportEnv(secretVault, path)
    if res.isErr: echo res.error; return 1
    return 0

  # ── session ──
  if args[1] == "session" and args.len >= 4 and args[2] == "list":
    var sm: SessionManager
    sm.init()
    ctlSessionList(sm, args[3]); return 0

  # ── tool ──
  if args[1] == "tool" and args.len >= 4 and args[2] == "install":
    ctlToolInstall(registryPath, args[3], args[4 ..^ 1]); return 0
  if args[1] == "tool" and args.len >= 3 and args[2] == "add-http":
    return ctlToolAddHttp(cfg.home, registryPath, args[3 ..^ 1])
  if args[1] == "traces":
    return ctlTraces(cfg.paddocks, args[2 ..^ 1])
  if args[1] == "mcp" and args.len >= 4 and args[2] == "login":
    return ctlMcpLogin(cfg.home, args[3], cfg.env, args[4 ..^ 1])

  # ── skill ──
  let skillsPath = cfg.home / "skills.toml"
  if args[1] == "skill" and args[2] == "install" and args.len >= 5:
    let r = ctlSkillInstall(cfg, skillsPath, args[3], args[4], args[5 ..^ 1])
    if r.isErr: return 1
    return 0
  if args[1] == "skill" and args[2] == "install" and args.len == 4:
    ## Remote install (slug only)
    let r = ctlSkillInstallRemote(cfg.home,
                          cfg.env.get("CLAWHUB_REGISTRY", ClawhubDefaultRegistry),
                          args[3])
    if r.isErr: return 1
    return 0
  if args[1] == "skill" and args[2] == "search" and args.len >= 4:
    let r = ctlSkillSearchRemote(cfg.env.get("CLAWHUB_REGISTRY", ClawhubDefaultRegistry), args[3])
    if r.isErr: return 1
    return 0
  if args[1] == "skill" and args[2] == "list" and args.len >= 3:
    ctlSkillList(skillsPath); return 0
  if args[1] == "skill" and args[2] == "update" and args.len >= 5:
    let r = ctlSkillUpdate(cfg, skillsPath, args[3], args[4], args[5 ..^ 1])
    if r.isErr: return 1
    return 0
  if args[1] == "skill" and args[2] == "update" and args.len >= 3:
    let slug = if args.len >= 4: args[3] else: ""
    let r = ctlSkillUpdateRemote(cfg.home,
                         cfg.env.get("CLAWHUB_REGISTRY", ClawhubDefaultRegistry),
                         slug)
    if r.isErr: return 1
    return 0

  # ── provider ──
  if args[1] == "provider" and args.len >= 4 and args[2] == "test":
    let r = ctlProviderTest(args[3], buildCompleteFnRef)
    if r.isErr: return 1
    return 0

  # ── schedule ──
  if args[1] == "schedule":
    ## Same state dir the daemon uses (`{home}/state`), so read-only commands
    ## work with the daemon stopped.
    return dispatchSchedule(cfg.home / "state", args)

  # ── memory ──
  when defined(withPostgres) or defined(withSqlite):
    proc makeMagmaMemory(): MdFileAdapter =
      MdFileAdapter(
        paddocksDir: cfg.paddocks,
        magmaDsn: cfg.env.get("DONKEY_PG_DSN"),
        magmaEnv: magmaEnvironment(cfg.env),
        magmaSqlitePath:
          block:
            cfg.env.get("DONKEY_MAGMA_SQLITE_PATH", cfg.home / "state" / "magma.sqlite"),
        magmaSqliteVectorPath: cfg.env.get("DONKEY_SQLITE_VEC_PATH", cfg.env.get("DONKEY_SQLITE_VECTOR_PATH")),
      )

    if args[1] == "memory" and args[2] == "search" and args.len >= 5:
      ctlMemorySearch(makeMagmaMemory(), args[3], args[4]); return 0
    if args[1] == "memory" and args[2] == "import" and args.len >= 4:
      ctlMemoryImport(makeMagmaMemory(), args[3]); return 0
    if args[1] == "memory" and args[2] == "ingest" and args.len >= 5:
      let uid = UserId(args[3])
      let mem = makeMagmaMemory()
      let ingested = ingestMemoryFile(
        mem.toRuntimePort(), uid, mem.paddockDir(uid), args[4],
        fs = newFsAdapter())
      if ingested.isErr:
        echo "ingest error: " & ingested.error
        return 1
      let stats = ingested.get()
      echo "Ingested " & $stats.chunks & " chunks (" & $stats.bytes &
           " bytes) from " & args[4]
      return 0
    if args[1] == "memory" and args[2] == "export" and args.len >= 4:
      let outDir = if args.len >= 5: args[4] else: ""
      ctlMemoryExport(makeMagmaMemory(), args[3], outDir); return 0
  else:
    if args[1] == "memory" and args[2] in ["search", "import", "ingest", "export"]:
      echo "This build disabled MAGMA support; rebuild with -d:withPostgres or -d:withSqlite"
      return 1

  # ── status ──
  if args[1] == "status" and args.len >= 2:
    let r = ctlStatus(cfg)
    if r.isErr: echo r.error; return 1
    return 0

  # ── unrecognized ──
  2
