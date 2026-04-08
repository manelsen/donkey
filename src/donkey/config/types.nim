## DonkeyConfig — typed, validated representation of donkey.toml.

import ../core/types
import ../core/security/dm_policy
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
    smOci    = "oci"     ## ephemeral OCI container with bind-mounted paddock
    smWasm   = "wasm"    ## embedded wasm3 runtime with WASI

  DonkeyConfig* = object
    home*:          string       ## Base dir; default: ~/.donkey
    logLevel*:      LogLevel     ## default: info
    logFile*:       string       ## Absolute path; empty = stderr only
    paddocks*:      string       ## User workspaces: {home}/paddocks/{uuid}/
    webAllowlist*:  seq[string]  ## Allowed public hosts for native web tools / skill net perms
    toolWebPolicy*: seq[ToolWebPolicy]
    skillNetPolicy*: seq[SkillNetPolicy]
    sandboxMode*:   SandboxMode  ## bash tool isolation; default: smNone
    sandboxRuntimeCmd*: string   ## OCI runtime CLI; default: "docker"
    sandboxImage*:  string       ## Container image for smOci; default: "alpine"
    wasmShellPath*: string       ## path to .wasm shell for smWasm; default: {home}/shell.wasm
    dmPolicy*:      DmPolicy     ## DM security policy; default: DmPolicyOpen
    wiring*:        bool         ## Enable advanced session wiring; default: false

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
    sandboxRuntimeCmd: "docker",
    sandboxImage: "alpine",
    wasmShellPath: home & "/shell.wasm",
    wiring:       false,
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
