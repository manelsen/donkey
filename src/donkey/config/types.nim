## DonkeyConfig — typed, validated representation of donkey.toml.

import ../core/types
import ../core/security/dm_policy
import ../core/app_meta
import ./environment
import ../domain/bots_pure
import ../domain/tools/github_pure   # GithubPolicy
export github_pure.GithubPolicy
import ../domain/a2a/a2a_client_pure   # A2aAgent
export a2a_client_pure.A2aAgent

export bots_pure

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
    smWasm   = "wasm"    ## wasmtime CLI running the busybox shell.wasm (app/sandbox)

  DonkeyConfig* = object
    home*:          string       ## Base dir; default: ~/.donkey
    logLevel*:      LogLevel     ## default: info
    logFile*:       string       ## Absolute path; empty = stderr only
    paddocks*:      string       ## User workspaces: {home}/paddocks/{uuid}/
    defaultProvider*: string     ## Instance-wide default provider for users without prefs
    defaultModel*:    string     ## Instance-wide default model for users without prefs
    webAllowlist*:  seq[string]  ## Allowed public hosts for native web tools / skill net perms
    toolWebPolicy*: seq[ToolWebPolicy]
    skillNetPolicy*: seq[SkillNetPolicy]
    invalidSandboxMode*: string  ## Original invalid sandbox mode from config; empty when valid
    sandboxMode*:   SandboxMode  ## bash tool isolation; default: smNone
    sandboxRuntimeCmd*: string   ## OCI runtime CLI; default: "docker"
    sandboxImage*:  string       ## Container image for smOci; default: "alpine"
    sandboxAllowHostFallback*: bool ## Allow OCI runtime failure to fall back to host exec
    sandboxAllowNetwork*: bool   ## Allow network egress inside OCI sandbox
    sandboxReadOnlyRootfs*: bool ## Keep OCI rootfs read-only outside mounted workspace/tmp
    wasmShellPath*: string       ## path to .wasm shell for smWasm; default: {home}/shell.wasm
    dmPolicy*:      DmPolicy     ## DM security policy; default: DmPolicyOpen
    invalidDmPolicy*: string     ## Raw invalid value from TOML/env; blocks startup
    wiring*:        bool         ## Enable advanced session wiring; default: false
    env*:           Environment  ## The environment snapshot the config was loaded with
    bots*:          seq[BotSpec] ## `[[bots]]` entries that are well formed (E3)
    githubPolicy*:  GithubPolicy ## `[github]`: what writes may do per repository (E11.3)
    githubPolicyError*: string   ## why `[github]` was not read; every write then asks
    a2aAgents*:     seq[A2aAgent] ## `[[a2a.agents]]`: whom delegate_to_agent may call (E13.4)
    a2aAgentsError*: string       ## why `[a2a]` was not read; no agent is then callable
    botProblems*:   seq[string]  ## why the other entries were left out

func defaultConfig*(home: string): DonkeyConfig =
  DonkeyConfig(
    home:         home,
    logLevel:     lvlInfo,
    logFile:      home & "/" & LogFileName,
    paddocks:     home & "/paddocks",
    defaultProvider: "",
    defaultModel: "",
    webAllowlist: @[],
    toolWebPolicy: @[],
    skillNetPolicy: @[],
    invalidSandboxMode: "",
    sandboxMode:  smNone,
    sandboxRuntimeCmd: "docker",
    sandboxImage: "alpine",
    sandboxAllowHostFallback: false,
    sandboxAllowNetwork: false,
    sandboxReadOnlyRootfs: true,
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
