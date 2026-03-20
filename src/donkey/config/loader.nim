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

type
  MainConfigPatch* = object
    logLevel*: Option[LogLevel]
    logFile*:  Option[string]
    paddocks*: Option[string]

  SandboxConfigPatch* = object
    sandboxMode*:  Option[SandboxMode]
    sandboxImage*: Option[string]

proc resolveHomeFromEnv*(homeEnv: string): string =
  if homeEnv.len > 0:
    return homeEnv
  expandTilde("~/" & HomeDirName)

proc resolveHome*(): string =
  resolveHomeFromEnv(getEnv(EnvHome))

proc parseSandboxMode*(rawMode: string): SandboxMode =
  case rawMode.strip().toLowerAscii()
  of "docker": smDocker
  else:        smNone

proc parseMainConfigPatch*(doc: TomlValueRef): MainConfigPatch =
  if not doc.hasKey(ConfigSectionName):
    return
  let mainSection = doc[ConfigSectionName]

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

proc parseSandboxConfigPatch*(doc: TomlValueRef): SandboxConfigPatch =
  if not doc.hasKey("sandbox"):
    return
  let sandboxSection = doc["sandbox"]

  if sandboxSection.hasKey("mode"):
    result.sandboxMode = some(parseSandboxMode(sandboxSection["mode"].getStr()))

  if sandboxSection.hasKey("image"):
    let sandboxImage = sandboxSection["image"].getStr().strip()
    if sandboxImage.len > 0:
      result.sandboxImage = some(sandboxImage)

proc applyMainConfigPatch*(patch: MainConfigPatch; cfg: DonkeyConfig): DonkeyConfig =
  result = cfg
  if patch.logLevel.isSome:
    result.logLevel = patch.logLevel.get()
  if patch.logFile.isSome:
    result.logFile = patch.logFile.get()
  if patch.paddocks.isSome:
    result.paddocks = patch.paddocks.get()

proc applySandboxConfigPatch*(patch: SandboxConfigPatch; cfg: DonkeyConfig): DonkeyConfig =
  result = cfg
  if patch.sandboxMode.isSome:
    result.sandboxMode = patch.sandboxMode.get()
  if patch.sandboxImage.isSome:
    result.sandboxImage = patch.sandboxImage.get()

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
  let sandboxPatch = parseSandboxConfigPatch(doc)
  result =
    baseConfig |>->
    applyMainConfigPatch(mainPatch) |>->
    applySandboxConfigPatch(sandboxPatch)
