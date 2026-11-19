## ctl_handler.nim — Dispatch all `donkey ctl` subcommands.
##
## Thin facade over the `donkey/ctl/*` handler modules: each subcommand group
## has its own module under `ctl/`, re-exported here so `import
## donkey/ctl_handler` keeps exposing every `ctl*` proc. `dispatchCtl` routes
## to the right one; `dispatchSchedule` routes the `schedule` subcommands.

import std/[options, os, strutils]
import core/types
import core/pipeops
import config/types
import config/dotenv
import config/loader
import config/clawhub_registry
import ports/provider
import adapters/memory/md_file
import adapters/state/pairing_store
import adapters/state/approval_store
import adapters/secrets/vault
import app/session_manager
import app/tools/memory_ingest_io
import adapters/memory/multigraph_runtime
import adapters/filesystem/fs_adapter
import ctl/user
import ctl/pairing
import ctl/approval
import ctl/secrets
import ctl/sessions
import ctl/skills
import ctl/providers
import ctl/schedule

export user, pairing, approval, secrets, sessions, skills, providers, schedule

# ── dispatch ───────────────────────────────────────────────────────────────────

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
    let path = if args.len >= 4: args[3] else: envFilePath(resolveHome())
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

  # ── skill ──
  let skillsPath = cfg.home / "skills.toml"
  if args[1] == "skill" and args[2] == "install" and args.len >= 5:
    let r = ctlSkillInstall(cfg, skillsPath, args[3], args[4], args[5 ..^ 1])
    if r.isErr: return 1
    return 0
  if args[1] == "skill" and args[2] == "install" and args.len == 4:
    ## Remote install (slug only)
    let r = ctlSkillInstallRemote(cfg.home,
                          getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry),
                          args[3])
    if r.isErr: return 1
    return 0
  if args[1] == "skill" and args[2] == "search" and args.len >= 4:
    let r = ctlSkillSearchRemote(getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry), args[3])
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
                         getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry),
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
