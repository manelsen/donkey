## service_handler.nim — Dispatch all `donkey service` subcommands.
##
## Owns systemd --user service install/remove/start/stop/restart/logs.
## Extracted from main() so the entrypoint stays lean.

import std/[os, strutils]
import ../core/app_meta

# ── templates & constants ──────────────────────────────────────────────────────

const EnvFileTemplate* = """# """ & AppName & """ environment — fill in the values you need.
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
QQ_OFFICIAL_APP_ID=
QQ_OFFICIAL_CLIENT_SECRET=
# QQ_OFFICIAL_API_BASE=https://api.sgroup.qq.com
# QQ_OFFICIAL_TOKEN_BASE=https://bots.qq.com

ZAI_API_KEY=
ZAI_CODING_API_KEY=
ZAI_ANTHROPIC_API_KEY=
OPENROUTER_API_KEY=
OPENAI_API_KEY=
DEEPSEEK_API_KEY=
ANTHROPIC_API_KEY=
GEMINI_API_KEY=
MINIMAX_API_KEY=
OPENCODE_API_KEY=

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

proc svcRun(cmd: string): bool =
  execShellCmd(cmd) == 0

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

# ── service command handlers ───────────────────────────────────────────────────

proc ctlServiceInstall*() =
  # Directories
  createDir(svcUnitDir())
  createDir(svcCfgDir())

  # Service unit file — points at the actual binary so nimble build takes
  # effect on next restart without reinstalling.
  let binPath = getAppFilename()
  writeFile(svcUnitFile(), buildServiceFileContent(binPath))
  echo "  binary  → " & binPath & " (in-place, no copy)"
  echo "  service → " & svcUnitFile()

  # Env file — create if missing, then inject any keys found in current env
  let envPath = svcCfgDir() / EnvFileName
  if not fileExists(envPath):
    writeFile(envPath, EnvFileTemplate)
    discard svcRun("chmod 600 " & envPath)

  const knownKeys = [
    "TELEGRAM_BOT_TOKEN", "DISCORD_BOT_TOKEN",
    "WECOM_CORP_ID", "WECOM_CORP_SECRET", "WECOM_AGENT_ID",
    "WECOM_CALLBACK_TOKEN", "WECHAT_APP_ID", "WECHAT_APP_SECRET",
    "WECHAT_CALLBACK_TOKEN", "WECHAT_TEMPLATE_ID",
    "FEISHU_APP_ID", "FEISHU_APP_SECRET",
    "FEISHU_VERIFICATION_TOKEN",
    "QQ_ONEBOT_URL", "QQ_ONEBOT_TOKEN",
    "QQ_OFFICIAL_APP_ID", "QQ_OFFICIAL_CLIENT_SECRET",
    "QQ_OFFICIAL_API_BASE", "QQ_OFFICIAL_TOKEN_BASE",
    "ZAI_API_KEY", "ZAI_CODING_API_KEY", "ZHIPU_API_KEY",
    "OPENROUTER_API_KEY", "ANTHROPIC_API_KEY",
    "GEMINI_API_KEY", "MINIMAX_API_KEY",
    "OPENCODE_API_KEY",
    "BRAVE_API_KEY", "DONKEY_PG_DSN", "DONKEY_SQLITE_VEC_PATH",
    "DONKEY_SQLITE_VECTOR_PATH",
  ]
  var envContent = readFile(envPath)
  var injected: seq[string]
  for k in knownKeys:
    let v = getEnv(k)
    if v.len == 0: continue
    var lines = envContent.splitLines()
    var found = false
    for i in 0 ..< lines.len:
      if lines[i].startsWith(k & "="):
        lines[i] = k & "=" & v
        found = true
        break
    if not found:
      lines.add(k & "=" & v)
    envContent = lines.join("\n")
    injected.add(k)
  writeFile(envPath, envContent)

  if injected.len > 0:
    echo "  env     → " & envPath & " (injected: " & injected.join(", ") & ")"
  else:
    echo "  env     → " & envPath & " (no keys in current env — fill in manually)"

  # Toml config — create if missing
  let tomlPath = svcCfgDir() / ConfigFileName
  if not fileExists(tomlPath):
    writeFile(tomlPath, TomlTemplate)
    echo "  config  → " & tomlPath
  else:
    echo "  config  → " & tomlPath & " (already exists — kept)"

  # Register with systemd
  discard svcRun("systemctl --user daemon-reload")
  if svcRun("systemctl --user enable " & AppSlug):
    echo ""
    echo "✓ Installed. Run: " & AppSlug & " service start"
    echo "  Logs:         " & AppSlug & " service logs -f"
    echo "  Auto-start:   loginctl enable-linger " & getEnv("USER", "your-user")
  else:
    echo "Warning: systemctl enable failed — is systemd --user running?"

proc ctlServiceRemove*() =
  discard svcRun("systemctl --user stop " & AppSlug)
  discard svcRun("systemctl --user disable " & AppSlug)
  if fileExists(svcUnitFile()):
    removeFile(svcUnitFile())
    echo "Removed " & svcUnitFile()
  discard svcRun("systemctl --user daemon-reload")
  echo "✓ Service removed. Config preserved at " & svcCfgDir()

proc ctlServiceStart*() =
  if not svcRun("systemctl --user start " & AppSlug):
    echo "Failed. Check: " & AppSlug & " service logs -f"
  else:
    echo "✓ Started. Logs: " & AppSlug & " service logs -f"

proc ctlServiceStop*() =
  if not svcRun("systemctl --user stop " & AppSlug):
    echo "Failed."
  else:
    echo "✓ Stopped."

proc ctlServiceRestart*() =
  if not svcRun("systemctl --user restart " & AppSlug):
    echo "Failed. Check: " & AppSlug & " service logs -f"
  else:
    echo "✓ Restarted. Logs: " & AppSlug & " service logs -f"

proc ctlServiceLogs*(follow: bool) =
  var cmd = "journalctl --user -u " & AppSlug & " --no-pager -o cat"
  if follow: cmd.add(" -f")
  discard execShellCmd(cmd)

# ── dispatch ───────────────────────────────────────────────────────────────────

proc dispatchService*(args: seq[string]; logsFollow: bool): int =
  ## Routes service subcommands. Returns exit code (0=ok, 2=unrecognized).
  if args.len < 2: return 2
  case args[1]
  of "install": ctlServiceInstall(); 0
  of "remove":  ctlServiceRemove();  0
  of "start":   ctlServiceStart();   0
  of "stop":    ctlServiceStop();    0
  of "restart": ctlServiceRestart(); 0
  of "logs":    ctlServiceLogs(logsFollow); 0
  else: 2
