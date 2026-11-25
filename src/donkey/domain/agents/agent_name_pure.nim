## agent_name_pure — what an agent name may be. On its own, without the
## agent's tools, so configuration can check a name without importing them.

import std/strutils

const MaxAgentNameLen* = 32

func validAgentName*(name: string): bool =
  ## Lower-case letters, digits and '-', up to 32: safe as a file name.
  name.len in 1 .. MaxAgentNameLen and
    name.allCharsInSet({'a' .. 'z', '0' .. '9', '-'})
