## Central app metadata.
##
## Keep product naming, file naming and well-known paths here so the runtime
## does not spread hardcoded project names across modules.

import std/strutils

func packageVersion(nimble: string): string =
  ## The `version = "x.y.z"` line of a .nimble file.
  for line in nimble.splitLines:
    let trimmed = line.strip
    if trimmed.startsWith("version") and '=' in trimmed:
      return trimmed.split('=', 1)[1].strip.strip(chars = {'"'})

const
  AppName*           = "Donkey"
  AppSlug*           = "donkey"
  AppVersion*        = packageVersion(staticRead("../../../donkey.nimble"))
    ## Read from donkey.nimble at compile time: the package version is the
    ## only one to bump.
  HomeDirName*       = ".donkey"
  ConfigDirName*     = "donkey"
  ConfigFileName*    = "donkey.toml"
  EnvFileName*       = "donkey.env"
  SockFileName*      = "donkey.sock"
  LogFileName*       = "donkey.log"
  ServiceUnitName*   = "donkey.service"
  ConfigSectionName* = "donkey"
  MermaidTempPrefix* = "donkey_mermaid_"
  PgMemoryTableName* = "donkey_memories"
  PgGraphName*       = "donkey_graph"
  ProjectUrl*        = "https://github.com/manelsen/donkey"
    ## Where Donkey lives: the HTTP-Referer gateways attribute usage to.
  OpenRouterRefererUrl* = ProjectUrl
