## service_handler.nim — Dispatch all `donkey service` subcommands.
##
## Owns systemd --user service install/remove/start/stop/restart/logs.
## Extracted from main() so the entrypoint stays lean.

import ../config/environment
import std/[os, strutils]
import ../core/app_meta
import ../domain/providers/descriptors
import ../core/pipeops
import ../ports/fs
import ../ports/process

# ── templates & constants ──────────────────────────────────────────────────────

const EnvFileHeader* = """# """ & AppName & """ environment — fill in the values you need.
# Permissions: chmod 600 ~/.config/""" & ConfigDirName & "/" & EnvFileName & """

TELEGRAM_BOT_TOKEN=
DISCORD_BOT_TOKEN=
WECOM_CORP_ID=
WECOM_CORP_SECRET=
WECOM_AGENT_ID=
WECOM_CALLBACK_TOKEN=
WECHAT_APP_ID=
WECHAT_APP_SECRET=
WECHAT_CALLBACK_TOKEN=
WECHAT_TEMPLATE_ID=
FEISHU_APP_ID=
FEISHU_APP_SECRET=
FEISHU_VERIFICATION_TOKEN=
QQ_ONEBOT_URL=
QQ_ONEBOT_TOKEN=
QQ_ONEBOT_SECRET=
# QQ_ONEBOT_WEBHOOK_HOST=127.0.0.1  (non-loopback requires QQ_ONEBOT_SECRET)
QQ_OFFICIAL_APP_ID=
QQ_OFFICIAL_CLIENT_SECRET=
# QQ_OFFICIAL_API_BASE=https://api.sgroup.qq.com
# QQ_OFFICIAL_TOKEN_BASE=https://bots.qq.com
"""

const EnvFileTail* = """
BRAVE_API_KEY=
# SQLite-first runtime (default):
# DONKEY_MAGMA_SQLITE_PATH=/path/to/donkey-magma.sqlite
# DONKEY_SQLITE_VEC_PATH=/absolute/path/to/vec0
#
# Optional PostgreSQL for larger Multigraph Memory installs:
#   docker compose up -d postgres
#   if 5432 is busy: DONKEY_PG_PORT=5433 docker compose up -d postgres
# DONKEY_PG_DSN=host=127.0.0.1 user=postgres password=donkey_pass dbname=donkey port=5432
"""

# Channel and tooling credentials stay curated text; provider keys come from
# providerDescriptors().
const ServiceAuxEnvKeys = [
  "TELEGRAM_BOT_TOKEN", "DISCORD_BOT_TOKEN",
  "WECOM_CORP_ID", "WECOM_CORP_SECRET", "WECOM_AGENT_ID",
  "WECOM_CALLBACK_TOKEN", "WECHAT_APP_ID", "WECHAT_APP_SECRET",
  "WECHAT_CALLBACK_TOKEN", "WECHAT_TEMPLATE_ID",
  "FEISHU_APP_ID", "FEISHU_APP_SECRET",
  "FEISHU_VERIFICATION_TOKEN",
  "QQ_ONEBOT_URL", "QQ_ONEBOT_TOKEN", "QQ_ONEBOT_SECRET",
  "QQ_ONEBOT_WEBHOOK_HOST",
  "QQ_OFFICIAL_APP_ID", "QQ_OFFICIAL_CLIENT_SECRET",
  "QQ_OFFICIAL_API_BASE", "QQ_OFFICIAL_TOKEN_BASE",
  "BRAVE_API_KEY", "DONKEY_PG_DSN", "DONKEY_SQLITE_VEC_PATH",
  "DONKEY_SQLITE_VECTOR_PATH",
]

func serviceEnvKeys*(): seq[string] =
  ## Env keys `service install` copies from the current environment.
  for key in ServiceAuxEnvKeys:
    if key notin result:
      result.add key
  for descriptor in providerDescriptors():
    for envName in descriptor.envNames:
      if envName notin result:
        result.add envName

proc buildEnvFileTemplate*(): string =
  ## Scaffold written to ~/.config/donkey/donkey.env on `service install`.
  ## One placeholder per provider, derived from the descriptor table.
  result = EnvFileHeader
  result.add "\n"
  var seen: seq[string]
  for descriptor in providerDescriptors():
    if descriptor.envNames.len == 0:
      continue
    let envName = descriptor.envNames[0]
    if envName in seen:
      continue
    seen.add envName
    result.add envName & "=\n"
  result.add "\n"
  result.add EnvFileTail

const TomlTemplate* = """# """ & AppName & """ configuration

[""" & ConfigSectionName & """]
# log_level = "info"    # debug | info | warn | error
# log_file  = ""        # leave empty to log to stderr (journald)

[security]
# web_allowlist = ["docs.nim-lang.org", "api.github.com"]
# When non-empty, native web tools and Deno skill --allow-net permissions
# must stay within these public hosts/subdomains.

[sandbox]
# mode  = "none"        # "none", "oci" or "wasm"
# runtime = "docker"    # OCI runtime CLI when mode = "oci"
# image = "alpine"
"""

# ── helpers ────────────────────────────────────────────────────────────────────

proc svcUnitDir*(): string = getHomeDir() / ".config" / "systemd" / "user"
proc svcUnitFile*(): string = svcUnitDir() / ServiceUnitName
proc svcCfgDir*(): string  = getHomeDir() / ".config" / ConfigDirName

proc svcRun(process: ProcessRuntimePort; cmd: string): bool =
  ## systemctl and journalctl talk to the terminal directly.
  let ran = process.run(ProcessSpec(command: cmd, passthrough: true))
  ran.isOk and ran.get.exitCode == 0

proc buildServiceFileContent*(binPath: string): string =
  ## Generates the systemd unit file pointing at the actual binary path.
  ## nimble build takes effect on next service restart — no reinstall needed.
  "[Unit]\n" &
  "Description=Donkey AI Agent Daemon\n" &
  "After=network.target\n" &
  "Wants=network.target\n" &
  "\n[Service]\n" &
  "Type=simple\n" &
  "EnvironmentFile=" & svcCfgDir() / EnvFileName & "\n" &
  "ExecStart=" & binPath & " start --config " & svcCfgDir() / ConfigFileName & "\n" &
  "Restart=on-failure\n" &
  "RestartSec=5s\n" &
  "TimeoutStopSec=10s\n" &
  "\n[Install]\n" &
  "WantedBy=default.target\n"

func withServiceKeys(envContent: string; env: Environment):
                    tuple[content: string, injected: seq[string]] =
  ## The env file with every service key found in `env` set, replacing an
  ## existing line or adding one.
  result.content = envContent
  for k in serviceEnvKeys():
    let v = env.get(k)
    if v.len == 0: continue
    var lines = result.content.splitLines()
    var found = false
    for i in 0 ..< lines.len:
      if lines[i].startsWith(k & "="):
        lines[i] = k & "=" & v
        found = true
        break
    if not found:
      lines.add(k & "=" & v)
    result.content = lines.join("\n")
    result.injected.add(k)

# ── service command handlers ───────────────────────────────────────────────────

proc ctlServiceInstall*(process: ProcessRuntimePort; fs: FsRuntimePort;
                        env: Environment): int =
  ## Keys already in `env` are copied into the service env file. 1 when a
  ## file could not be written.
  let dirs = fs.createDir(svcUnitDir()) and fs.createDir(svcCfgDir())
  if dirs.isErr:
    echo "Error: " & dirs.error
    return 1

  # Service unit file — points at the actual binary so nimble build takes
  # effect on next restart without reinstalling.
  let binPath = try: getAppFilename() except CatchableError: AppSlug
  fs.writeFile(svcUnitFile(), buildServiceFileContent(binPath)).isOkOr:
    echo "Error: " & error
    return 1
  echo "  binary  → " & binPath & " (in-place, no copy)"
  echo "  service → " & svcUnitFile()

  # Env file — create if missing (private: it holds keys), then inject any
  # keys found in the current env
  let envPath = svcCfgDir() / EnvFileName
  let current =
    if fs.entryKind(envPath) == fekFile: fs.readFile(envPath)
    else: Result[string, string].ok(buildEnvFileTemplate())
  let envContent = current.valueOr:
    echo "Error: " & error
    return 1
  let merged = withServiceKeys(envContent, env)
  ## 0600 from the first byte: the file holds API keys.
  fs.writePrivate(envPath, merged.content).isOkOr:
    echo "Error: " & error
    return 1

  if merged.injected.len > 0:
    echo "  env     → " & envPath & " (injected: " & merged.injected.join(", ") & ")"
  else:
    echo "  env     → " & envPath & " (no keys in current env — fill in manually)"

  # Toml config — create if missing
  let tomlPath = svcCfgDir() / ConfigFileName
  if fs.entryKind(tomlPath) == fekMissing:
    fs.writeFile(tomlPath, TomlTemplate).isOkOr:
      echo "Error: " & error
      return 1
    echo "  config  → " & tomlPath
  else:
    echo "  config  → " & tomlPath & " (already exists — kept)"

  # Register with systemd
  discard svcRun(process, "systemctl --user daemon-reload")
  if svcRun(process, "systemctl --user enable " & AppSlug):
    echo ""
    echo "✓ Installed. Run: " & AppSlug & " service start"
    echo "  Logs:         " & AppSlug & " service logs -f"
    echo "  Auto-start:   loginctl enable-linger " & env.get("USER", "your-user")
  else:
    echo "Warning: systemctl enable failed — is systemd --user running?"
  0

proc ctlServiceRemove*(process: ProcessRuntimePort; fs: FsRuntimePort) =
  discard svcRun(process, "systemctl --user stop " & AppSlug)
  discard svcRun(process, "systemctl --user disable " & AppSlug)
  if fs.entryKind(svcUnitFile()) == fekFile:
    let removed = fs.remove(svcUnitFile(), false)
    if removed.isOk: echo "Removed " & svcUnitFile()
    else: echo "Error: " & removed.error
  discard svcRun(process, "systemctl --user daemon-reload")
  echo "✓ Service removed. Config preserved at " & svcCfgDir()

proc ctlServiceStart*(process: ProcessRuntimePort) =
  if not svcRun(process, "systemctl --user start " & AppSlug):
    echo "Failed. Check: " & AppSlug & " service logs -f"
  else:
    echo "✓ Started. Logs: " & AppSlug & " service logs -f"

proc ctlServiceStop*(process: ProcessRuntimePort) =
  if not svcRun(process, "systemctl --user stop " & AppSlug):
    echo "Failed."
  else:
    echo "✓ Stopped."

proc ctlServiceRestart*(process: ProcessRuntimePort) =
  if not svcRun(process, "systemctl --user restart " & AppSlug):
    echo "Failed. Check: " & AppSlug & " service logs -f"
  else:
    echo "✓ Restarted. Logs: " & AppSlug & " service logs -f"

proc ctlServiceLogs*(process: ProcessRuntimePort; follow: bool) =
  var cmd = "journalctl --user -u " & AppSlug & " --no-pager -o cat"
  if follow: cmd.add(" -f")
  discard svcRun(process, cmd)

# ── dispatch ───────────────────────────────────────────────────────────────────

proc dispatchService*(process: ProcessRuntimePort; fs: FsRuntimePort;
                      args: seq[string]; logsFollow: bool; env: Environment): int =
  ## Routes service subcommands. Returns exit code (0=ok, 1=failed,
  ## 2=unrecognized).
  if args.len < 2: return 2
  case args[1]
  of "install": ctlServiceInstall(process, fs, env)
  of "remove":  ctlServiceRemove(process, fs); 0
  of "start":   ctlServiceStart(process);   0
  of "stop":    ctlServiceStop(process);    0
  of "restart": ctlServiceRestart(process); 0
  of "logs":    ctlServiceLogs(process, logsFollow); 0
  else: 2
