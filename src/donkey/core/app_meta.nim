## Central app metadata.
##
## Keep product naming, file naming and well-known paths here so the runtime
## does not spread hardcoded project names across modules.

const
  AppName*           = "Donkey"
  AppSlug*           = "donkey"
  AppVersion*        = "0.1.0"
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
  OpenRouterRefererUrl* = "https://github.com/donkey-ai/donkey"
