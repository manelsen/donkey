## The process environment, read once.
##
## `readEnvironment` is the only place that reads the process environment
## (checked by `tests/architecture/t_env_reads.nim`). The daemon and `ctl` take
## a snapshot after `donkey.env` and the secret vault have filled it in, and
## pass it down: code that needs a variable receives the snapshot or the typed
## settings parsed from it, never `getEnv`. A test builds one with
## `environmentOf` instead of mutating the process with `putEnv`.

import std/[os, strutils, tables]

type
  Environment* = object
    vars: Table[string, string]

func environmentOf*(pairs: openArray[(string, string)]): Environment =
  ## A snapshot from explicit pairs, for tests and for code that composes one.
  for (name, value) in pairs:
    result.vars[name] = value

proc readEnvironment*(): Environment =
  ## Snapshot of the process environment as it is now.
  for name, value in envPairs():
    result.vars[name] = value

func get*(env: Environment; name: string; default = ""): string =
  ## The value of `name`, or `default` when it is unset or empty (the same as
  ## `getEnv(name, default)` for an unset name; an empty value also yields the
  ## default, which is what every caller meant).
  let value = env.vars.getOrDefault(name)
  if value.len > 0: value else: default

func stripped*(env: Environment; name: string; default = ""): string =
  ## `get` with surrounding whitespace removed; blank counts as unset.
  let value = env.vars.getOrDefault(name).strip()
  if value.len > 0: value else: default

func has*(env: Environment; name: string): bool =
  ## Whether `name` is set to something other than blanks.
  env.vars.getOrDefault(name).strip().len > 0

func with*(env: Environment; name, value: string): Environment =
  ## A copy with `name` set, for tests and for layering sources.
  result = env
  result.vars[name] = value

iterator pairs*(env: Environment): (string, string) =
  for name, value in env.vars:
    yield (name, value)
