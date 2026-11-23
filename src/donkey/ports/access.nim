## Who may talk to the agent: a revoked user may not, and outside an open DM
## policy only a user on the DM allowlist may. Kept apart from the memory
## port; the revocation is read from the user's profile, the allowlist from
## its own store (`adapters/memory/dm_allowlist`).

import ../core/pipeops
import ../core/types

type
  ProfileCheck* = proc(userId: UserId): Result[bool, string] {.gcsafe, raises: [].}
    ## A question about the user; an Err when the answer cannot be read.

  AccessPort* = object
    isRevoked*:   ProfileCheck
    isDmAllowed*: ProfileCheck

proc revoked*(p: AccessPort; userId: UserId): bool {.gcsafe, raises: [].} =
  ## Fails closed: a profile that cannot be read counts as revoked. Without
  ## a check nobody is.
  if p.isRevoked == nil:
    return false
  p.isRevoked(userId).valueOr(true)

proc dmAllowed*(p: AccessPort; userId: UserId): bool {.gcsafe, raises: [].} =
  ## Fails closed: an allowlist that cannot be read allows nobody, and so
  ## does a port without one.
  if p.isDmAllowed == nil:
    return false
  p.isDmAllowed(userId).valueOr(false)
