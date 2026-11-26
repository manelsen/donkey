## standing_approvals — approvals that stand, on disk (ports/approval,
## PRD-roadmap E5.2). `{userId: [key, …]}` in a private JSON file written
## atomically; read once, kept in memory, used from the daemon loop only.

import std/[json, os, tables]
import ../../core/pipeops
import ../../ports/approval
import ./durable_file

const StandingApprovalsFile* = "standing_approvals.json"   ## in {home}/state

type StandingApprovals* = ref object
  path: string
  byUser: Table[string, seq[string]]

proc newStandingApprovals*(path: string): StandingApprovals =
  result = StandingApprovals(path: path)
  if not fileExists(path):
    return
  try:
    let j = parseJson(readFile(path))
    if j.kind == JObject:
      for user, keys in j.pairs:
        if keys.kind == JArray:
          for k in keys:
            if k.kind == JString:
              result.byUser.mgetOrPut(user, @[]).add k.getStr
  except CatchableError:
    discard   ## unreadable: nothing stands, everything is asked again

proc save(s: StandingApprovals): Result[void, string] {.raises: [].} =
  var j = newJObject()
  for user, keys in s.byUser:
    j[user] = %keys
  atomicWriteText(s.path, $j, "w")

proc toStandingPort*(s: StandingApprovals): StandingApprovalPort =
  StandingApprovalPort(
    has: proc(userId, key: string): bool {.gcsafe, raises: [].} =
      key in s.byUser.getOrDefault(userId),
    grant: proc(userId, key: string): Result[void, string] {.gcsafe, raises: [].} =
      if key notin s.byUser.getOrDefault(userId):
        s.byUser.mgetOrPut(userId, @[]).add key
        return s.save()
      ok(),
    revoke: proc(userId, key: string): Result[void, string] {.gcsafe, raises: [].} =
      var keys = s.byUser.getOrDefault(userId)
      let i = keys.find(key)
      if i < 0:
        return err("no standing approval " & key)
      keys.delete(i)
      s.byUser[userId] = keys
      s.save(),
    list: proc(userId: string): seq[string] {.gcsafe, raises: [].} =
      s.byUser.getOrDefault(userId))

proc entries*(s: StandingApprovals): seq[(string, string)] =
  ## Every (user, key) that stands, for the admin TUI.
  for user, keys in s.byUser:
    for k in keys:
      result.add (user, k)
