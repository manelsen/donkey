## inbound_gate — cross-channel DM authorization decision.
##
## Application layer: owns the `DmPolicy`/allowlist business rule and the
## `/continue <code>` admission exception. Channel adapters only provide an
## `IdentityGatePort` backed by their identity resolver; they must not encode
## this policy themselves.

import std/[options, strutils]
import ../core/commands/command_routing
import ../core/security/dm_policy
import ../core/types
import ../domain/message
import ./session_manager

type
  IdentityGatePort* = object
    ## Adapter-supplied identity operations. No I/O is performed here beyond
    ## what the resolver callbacks already do.
    lookup*:       proc(kind: ChannelKind; rawId: string): Option[UserId] {.gcsafe.}
    resolve*:      proc(kind: ChannelKind; rawId: string): UserId {.gcsafe.}
    peekLinkCode*: proc(code: string): Option[UserId] {.gcsafe.}

  InboundAuthorization* = object
    allowed*:    bool
    userId*:     UserId
    identified*: bool   ## false only when an unknown sender was denied

proc linkTargetFor*(gate: IdentityGatePort;
                    kind: ChannelKind;
                    text: string): Option[UserId] {.gcsafe.} =
  ## Returns the authorized UUID behind a `/continue <code>` command without
  ## consuming the code. The DM gate uses this to let an unknown identity link
  ## itself to an already-authorized account, while still rejecting everyone
  ## else before an identity is minted.
  let command = decideCommandRequest(CommandRequest(channel: kind, text: text))
  if command.route == crLocal and decideLocalCommandAction(command) == lcaContinueLink:
    return gate.peekLinkCode(command.value.strip)
  none(UserId)

proc authorizeInbound*(sm: SessionManager;
                       gate: IdentityGatePort;
                       kind: ChannelKind;
                       rawId: string;
                       text: string): InboundAuthorization {.gcsafe.} =
  ## Single DM gate shared by callback-style channels.
  ##
  ## Known identities are checked against the allowlist. New identities are
  ## minted only under `DmPolicyOpen` or when the message is `/continue <code>`
  ## and the code points at an already-authorized UUID (the handler consumes
  ## the code and rewrites the mapping). A denied sender is never persisted.
  let known = gate.lookup(kind, rawId)
  if known.isSome:
    result.userId = known.get
    result.identified = true
    result.allowed = sm.allows(result.userId)
  elif sm.dmPolicy == DmPolicyOpen:
    result.userId = gate.resolve(kind, rawId)
    result.identified = true
    result.allowed = sm.allows(result.userId)
  if not result.allowed:
    let target = linkTargetFor(gate, kind, text)
    if target.isSome and sm.allows(target.get):
      result.userId =
        if known.isSome: known.get
        else: gate.resolve(kind, rawId)
      result.identified = true
      result.allowed = true
