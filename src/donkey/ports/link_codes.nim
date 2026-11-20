## LinkCodePort — the cross-channel `/mycode` → `/continue` seam.
##
## A code is minted on one channel and redeemed on another, so the table
## cannot belong to a single adapter: every channel runtime asks this port
## instead of its own resolver. The implementation is the adapter that shares
## the table per identity file; the decision to continue belongs to the
## channel runtime, not here.

import std/options
import ../core/types

type
  LinkCodePort* = object
    mint*:   proc(userId: UserId): string {.gcsafe.}
    peek*:   proc(code: string): Option[UserId] {.gcsafe.}
      ## The target a valid code points at, without consuming it: the channel
      ## gate admits an unknown sender only when the code points at an
      ## authorized account.
    redeem*: proc(code: string): Option[UserId] {.gcsafe.}
      ## Consumes a valid code and returns its target; the caller performs the
      ## mapping, because only it knows the raw id of the speaker redeeming.

  IdentityLinkPort* = object
    ## The two halves of `/mycode` → `/continue` as one channel sees them:
    ## mint a code for the speaker, or link the speaker's raw id to the
    ## account a code points at. `link` is false for an unknown or expired
    ## code, or when the mapping could not be saved.
    mint*: proc(userId: UserId): string {.gcsafe.}
    link*: proc(code: string; channel: ChannelKind; rawId: string): bool {.gcsafe.}
