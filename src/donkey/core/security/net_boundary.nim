## net_boundary — global network egress policy.

import std/[strutils]
import ../pipeops

type
  NetPolicy* = object
    allowlist*: seq[string]
    denyAll*:   bool

proc isHostAllowed*(host: string, allowlist: seq[string]): bool =
  ## Returns true if host matches any entry in allowlist.
  ## Supports simple prefix matching or exact match.
  if host.len == 0: return false
  for entry in allowlist:
    if host == entry or host.endsWith("." & entry):
      return true
  false

proc validateEgress*(host: string, allowlist: seq[string]): Result[string, string] =
  ## Pure helper to validate egress in a pipe.
  if isHostAllowed(host, allowlist):
    ok(host)
  else:
    err("Network egress BLOCKED: host '" & host & "' not in allowlist")
