## CommandServicesPort — what the command dispatcher needs from the outside.
##
## The dispatcher in `app/command_dispatch` decides which command does what;
## this port gives it the effects (memory reads and writes, provider pings,
## diagnostics, skill installs) without importing adapters. Every operation
## returns `Result`: an implementation reports failures instead of raising,
## so no exception leaves a channel drain loop.

import ../core/pipeops
import ../core/types

type
  CommandTextFn* = proc(userId: UserId): Result[string, string] {.gcsafe.}
  CommandArgFn* = proc(userId: UserId; value: string): Result[string, string] {.gcsafe.}
  CommandCountFn* = proc(userId: UserId; sessionCount: int): Result[string, string] {.gcsafe.}

  CommandServicesPort* = object
    about*:       CommandCountFn  ## runtime overview
    doctor*:      CommandCountFn  ## diagnostics report
    status*:      CommandCountFn  ## provider, prefs and counters
    ping*:        CommandTextFn   ## round-trip to the user's provider
    memoryView*:  CommandTextFn   ## what the agent remembers about the user
    clearMemory*: proc(userId: UserId): Result[void, string] {.gcsafe.}
    skill*:       CommandArgFn    ## /skill subcommands
    models*:      CommandArgFn    ## /models text form
    think*:       CommandArgFn    ## /think text form
    budget*:      CommandArgFn    ## /budget text form
    channelPrefs*: proc(userId: UserId): Result[ChannelPrefs, string] {.gcsafe.}
    savePreference*: proc(userId: UserId; key, value: string): Result[void, string] {.gcsafe.}
    toolsCount*:       int
    toolClientsCount*: int
