## DonkeyConfig — typed, validated representation of donkey.toml.

import ../core/types

type
  SandboxMode* = enum
    smNone   = "none"    ## workingDir only — no OS-level isolation
    smDocker = "docker"  ## ephemeral container with bind-mounted paddock

  DonkeyConfig* = object
    home*:          string       ## Base dir; default: ~/.donkey
    logLevel*:      LogLevel     ## default: info
    logFile*:       string       ## Absolute path; empty = stderr only
    paddocks*:      string       ## User workspaces: {home}/paddocks/{uuid}/
    sandboxMode*:   SandboxMode  ## bash tool isolation; default: smNone
    sandboxImage*:  string       ## Docker image for smDocker; default: "alpine"

func defaultConfig*(home: string): DonkeyConfig =
  DonkeyConfig(
    home:         home,
    logLevel:     lvlInfo,
    logFile:      home & "/donkey.log",
    paddocks:     home & "/paddocks",
    sandboxMode:  smNone,
    sandboxImage: "alpine",
  )
