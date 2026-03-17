## DonkeyConfig — typed, validated representation of donkey.toml.

import ../core/types

type
  DonkeyConfig* = object
    home*:     string    ## Base dir; default: ~/.donkey
    logLevel*: LogLevel  ## default: info
    logFile*:  string    ## Absolute path; empty = stderr only
    paddocks*: string    ## User workspaces: {home}/paddocks/{uuid}/

func defaultConfig*(home: string): DonkeyConfig =
  DonkeyConfig(
    home:     home,
    logLevel: lvlInfo,
    logFile:  home & "/donkey.log",
    paddocks: home & "/paddocks",
  )
