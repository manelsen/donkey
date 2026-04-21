## Config loader — reads donkey.toml, applies env overrides, returns defaults
## gracefully when the file is missing or unparseable.
##
## Priority (highest to lowest):
##   1. DONKEY_HOME env var (for home dir only)
##   2. Values in donkey.toml
##   3. Built-in defaults (see config/types.nim)

import std/[options, os, strutils]
import parsetoml
import ./types
import ../core/types
import ../core/app_meta
import ../core/pipeops

export types

const EnvHome* = "DONKEY_HOME"
const EnvWebAllowlist* = "DONKEY_WEB_ALLOWLIST"

type
  MainConfigPatch* = object
    home*:     Option[string]
    logLevel*: Option[LogLevel]
    logFile*:  Option[string]
    paddocks*: Option[string]
    defaultProvider*: Option[string]
    defaultModel*: Option[string]
    wiring*:   Option[bool]

  SecurityConfigPatch* = object
    webAllowlist*: Option[seq[string]]
    toolWebPolicy*: Option[seq[ToolWebPolicy]]
    skillNetPolicy*: Option[seq[SkillNetPolicy]]

  SandboxConfigPatch* = object
    sandboxMode*:       Option[SandboxMode]
    sandboxRuntimeCmd*: Option[string]
    sandboxImage*:      Option[string]
    sandboxAllowHostFallback*: Option[bool]
    sandboxAllowNetwork*: Option[bool]
    sandboxReadOnlyRootfs*: Option[bool]

proc resolveHomeFromEnv*(homeEnv: string): string =
  if homeEnv.len > 0:
    return homeEnv
  expandTilde("~/" & HomeDirName)

proc resolveHome*(): string =
  resolveHomeFromEnv(getEnv(EnvHome))

proc parseSandboxMode*(rawMode: string): SandboxMode =
  case rawMode.strip().toLowerAscii()
  of "docker", "oci": smOci
  of "wasm":   smWasm
  of "wasmer": smWasmer
  else:        smNone

proc parseHostList*(raw: string): seq[string] =
  for item in raw.split(','):
    let host = item.strip().toLowerAscii()
    if host.len > 0:
      result.add(host)

proc parseHostList*(items: seq[string]): seq[string] =
  for item in items:
    result.add(parseHostList(item))

proc parseWebAccessRule*(raw: string): WebAccessRule =
  let trimmed = raw.strip()
  let withoutScheme =
    if "://" in trimmed: trimmed[trimmed.find("://") + 3 .. ^1] else: trimmed
  let withoutQuery =
    block:
      var v = withoutScheme
      for i, c in v:
        if c in {'?', '#'}:
          v = v[0 ..< i]
          break
      v
  let slash = withoutQuery.find('/')
  if slash < 0:
    return WebAccessRule(host: withoutQuery.toLowerAscii(), pathPrefix: "")
  let rawPrefix = withoutQuery[slash .. ^1]
  WebAccessRule(
    host: withoutQuery[0 ..< slash].toLowerAscii(),
    pathPrefix: if rawPrefix == "/" or rawPrefix.len == 0: "" else: rawPrefix,
  )

proc parseWebAccessRules*(node: TomlValueRef): seq[WebAccessRule] =
  case node.kind
  of TomlValueKind.String:
    result.add(parseWebAccessRule(node.getStr()))
  of TomlValueKind.Array:
    for item in node.getElems():
      result.add(parseWebAccessRule(item.getStr()))
  else:
    discard

proc parseSecurityConfigPatch*(doc: TomlValueRef): SecurityConfigPatch =
  if not doc.hasKey("security"):
    return
  let securitySection = doc["security"]
  if securitySection.hasKey("web_allowlist"):
    let node = securitySection["web_allowlist"]
    case node.kind
    of TomlValueKind.String:
      result.webAllowlist = some(parseHostList(node.getStr()))
    of TomlValueKind.Array:
      var hosts: seq[string] = @[]
      for item in node.getElems():
        hosts.add(parseHostList(item.getStr()))
      result.webAllowlist = some(hosts)
    else:
      discard

  if securitySection.hasKey("tools"):
    let toolsSection = securitySection["tools"]
    if toolsSection.kind == TomlValueKind.Table:
      var toolPolicy: seq[ToolWebPolicy] = @[]
      for toolName, toolNode in toolsSection.tableVal.pairs:
        if toolNode.kind == TomlValueKind.Table and toolNode.hasKey("allow"):
          toolPolicy.add(ToolWebPolicy(
            toolName: toolName,
            allow: parseWebAccessRules(toolNode["allow"]),
          ))
      result.toolWebPolicy = some(toolPolicy)

  if securitySection.hasKey("skills"):
    let skillsSection = securitySection["skills"]
    if skillsSection.kind == TomlValueKind.Table:
      var skillPolicy: seq[SkillNetPolicy] = @[]
      for skillName, skillNode in skillsSection.tableVal.pairs:
        if skillNode.kind == TomlValueKind.Table and skillNode.hasKey("allow_net"):
          let allowNet = skillNode["allow_net"]
          var hosts: seq[string] = @[]
          case allowNet.kind
          of TomlValueKind.String:
            hosts = parseHostList(allowNet.getStr())
          of TomlValueKind.Array:
            for item in allowNet.getElems():
              hosts.add(parseHostList(item.getStr()))
          else:
            discard
          skillPolicy.add(SkillNetPolicy(
            skillName: skillName,
            allowNetHosts: hosts,
          ))
      result.skillNetPolicy = some(skillPolicy)

proc applySecurityConfigPatch*(patch: SecurityConfigPatch; cfg: DonkeyConfig): DonkeyConfig =
  result = cfg
  if patch.webAllowlist.isSome:
    result.webAllowlist = patch.webAllowlist.get()
  if patch.toolWebPolicy.isSome:
    result.toolWebPolicy = patch.toolWebPolicy.get()
  if patch.skillNetPolicy.isSome:
    result.skillNetPolicy = patch.skillNetPolicy.get()

proc applyEnvOverrides*(cfg: DonkeyConfig): DonkeyConfig =
  result = cfg
  let rawAllowlist = getEnv(EnvWebAllowlist).strip()
  if rawAllowlist.len > 0:
    result.webAllowlist = parseHostList(rawAllowlist)

proc parseMainConfigPatch*(doc: TomlValueRef): MainConfigPatch =
  if not doc.hasKey(ConfigSectionName):
    return
  let mainSection = doc[ConfigSectionName]

  if mainSection.hasKey("home"):
    let homeVal = mainSection["home"].getStr().strip()
    if homeVal.len > 0:
      result.home = some(expandTilde(homeVal))

  if mainSection.hasKey("log_level"):
    result.logLevel = some(parseLogLevel(mainSection["log_level"].getStr()))

  if mainSection.hasKey("log_file"):
    let logFile = mainSection["log_file"].getStr().strip()
    if logFile.len > 0:
      result.logFile = some(expandTilde(logFile))

  if mainSection.hasKey("paddocks"):
    let paddocks = mainSection["paddocks"].getStr().strip()
    if paddocks.len > 0:
      result.paddocks = some(expandTilde(paddocks))

  if mainSection.hasKey("default_provider"):
    let defaultProvider = mainSection["default_provider"].getStr().strip()
    if defaultProvider.len > 0:
      result.defaultProvider = some(defaultProvider)

  if mainSection.hasKey("default_model"):
    let defaultModel = mainSection["default_model"].getStr().strip()
    if defaultModel.len > 0:
      result.defaultModel = some(defaultModel)

  if mainSection.hasKey("wiring"):
    result.wiring = some(mainSection["wiring"].getBool())

proc parseSandboxConfigPatch*(doc: TomlValueRef): SandboxConfigPatch =
  if not doc.hasKey("sandbox"):
    return
  let sandboxSection = doc["sandbox"]

  if sandboxSection.hasKey("mode"):
    result.sandboxMode = some(parseSandboxMode(sandboxSection["mode"].getStr()))

  if sandboxSection.hasKey("runtime"):
    let sandboxRuntime = sandboxSection["runtime"].getStr().strip()
    if sandboxRuntime.len > 0:
      result.sandboxRuntimeCmd = some(sandboxRuntime)

  if sandboxSection.hasKey("image"):
    let sandboxImage = sandboxSection["image"].getStr().strip()
    if sandboxImage.len > 0:
      result.sandboxImage = some(sandboxImage)

  if sandboxSection.hasKey("allow_host_fallback"):
    result.sandboxAllowHostFallback = some(sandboxSection["allow_host_fallback"].getBool())
  if sandboxSection.hasKey("allow_network"):
    result.sandboxAllowNetwork = some(sandboxSection["allow_network"].getBool())
  if sandboxSection.hasKey("read_only_rootfs"):
    result.sandboxReadOnlyRootfs = some(sandboxSection["read_only_rootfs"].getBool())

proc applyMainConfigPatch*(patch: MainConfigPatch; cfg: DonkeyConfig): DonkeyConfig =
  result = cfg
  if patch.home.isSome:
    result.home = patch.home.get()
  if patch.logLevel.isSome:
    result.logLevel = patch.logLevel.get()
  if patch.logFile.isSome:
    result.logFile = patch.logFile.get()
  if patch.paddocks.isSome:
    result.paddocks = patch.paddocks.get()
  if patch.defaultProvider.isSome:
    result.defaultProvider = patch.defaultProvider.get()
  if patch.defaultModel.isSome:
    result.defaultModel = patch.defaultModel.get()
  if patch.wiring.isSome:
    result.wiring = patch.wiring.get()

proc applySandboxConfigPatch*(patch: SandboxConfigPatch; cfg: DonkeyConfig): DonkeyConfig =
  result = cfg
  if patch.sandboxMode.isSome:
    result.sandboxMode = patch.sandboxMode.get()
  if patch.sandboxRuntimeCmd.isSome:
    result.sandboxRuntimeCmd = patch.sandboxRuntimeCmd.get()
  if patch.sandboxImage.isSome:
    result.sandboxImage = patch.sandboxImage.get()
  if patch.sandboxAllowHostFallback.isSome:
    result.sandboxAllowHostFallback = patch.sandboxAllowHostFallback.get()
  if patch.sandboxAllowNetwork.isSome:
    result.sandboxAllowNetwork = patch.sandboxAllowNetwork.get()
  if patch.sandboxReadOnlyRootfs.isSome:
    result.sandboxReadOnlyRootfs = patch.sandboxReadOnlyRootfs.get()

proc loadTomlConfig*(path: string): Option[TomlValueRef] =
  if not fileExists(path):
    return none(TomlValueRef)
  try:
    some(parseFile(path))
  except:
    none(TomlValueRef)

proc loadConfig*(path: string): DonkeyConfig =
  let baseConfig = defaultConfig(resolveHome())
  let docOpt = loadTomlConfig(path)
  if docOpt.isNone:
    return baseConfig

  let doc = docOpt.get()
  let mainPatch = parseMainConfigPatch(doc)
  let securityPatch = parseSecurityConfigPatch(doc)
  let sandboxPatch = parseSandboxConfigPatch(doc)
  result =
    baseConfig |>->
    applyMainConfigPatch(mainPatch) |>->
    applySecurityConfigPatch(securityPatch) |>->
    applySandboxConfigPatch(sandboxPatch)
  result = result |> applyEnvOverrides
