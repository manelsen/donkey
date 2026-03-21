## DonkeyConfig — typed, validated representation of donkey.toml.

import ../core/types
import ../core/app_meta

type
  WebAccessRule* = object
    host*:       string
    pathPrefix*: string

  ToolWebPolicy* = object
    toolName*: string
    allow*:    seq[WebAccessRule]

  SkillNetPolicy* = object
    skillName*:     string
    allowNetHosts*: seq[string]

  SandboxMode* = enum
    smNone   = "none"    ## workingDir only — no OS-level isolation
    smDocker = "docker"  ## ephemeral container with bind-mounted paddock

  DonkeyConfig* = object
    home*:          string       ## Base dir; default: ~/.donkey
    logLevel*:      LogLevel     ## default: info
    logFile*:       string       ## Absolute path; empty = stderr only
    paddocks*:      string       ## User workspaces: {home}/paddocks/{uuid}/
    webAllowlist*:  seq[string]  ## Allowed public hosts for native web tools / skill net perms
    toolWebPolicy*: seq[ToolWebPolicy]
    skillNetPolicy*: seq[SkillNetPolicy]
    sandboxMode*:   SandboxMode  ## bash tool isolation; default: smNone
    sandboxImage*:  string       ## Docker image for smDocker; default: "alpine"

func defaultConfig*(home: string): DonkeyConfig =
  DonkeyConfig(
    home:         home,
    logLevel:     lvlInfo,
    logFile:      home & "/" & LogFileName,
    paddocks:     home & "/paddocks",
    webAllowlist: @[],
    toolWebPolicy: @[],
    skillNetPolicy: @[],
    sandboxMode:  smNone,
    sandboxImage: "alpine",
  )

func hostOnlyRule*(host: string): WebAccessRule =
  WebAccessRule(host: host, pathPrefix: "")

func effectiveToolWebRules*(cfg: DonkeyConfig; toolName: string): seq[WebAccessRule] =
  for policy in cfg.toolWebPolicy:
    if policy.toolName == toolName:
      return policy.allow
  for host in cfg.webAllowlist:
    result.add(hostOnlyRule(host))

func effectiveSkillAllowNetHosts*(cfg: DonkeyConfig; skillName: string): seq[string] =
  for policy in cfg.skillNetPolicy:
    if policy.skillName == skillName:
      return policy.allowNetHosts
  cfg.webAllowlist
