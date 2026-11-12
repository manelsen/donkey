## inbound_gate — cross-channel DM authorization decision.
##
## Application layer: owns the `DmPolicy`/allowlist business rule and the
## `/continue <code>` admission exception. Channel adapters only provide an
## `IdentityGatePort` backed by their identity resolver; they must not encode
## this policy themselves.

import std/[options, strutils]
import ../core/commands/command_routing
import ../core/log
import ../core/pipeops
import ../core/security/dm_policy
import ../core/types
import ../domain/message
import ./session_manager

let gateLog = newLogger("inbound.gate")

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

  InboundLinkSource* = enum
    ilsNone          ## do not admit link commands (e.g. button clicks)
    ilsCommandText   ## parse `/continue <code>` from the message text
    ilsBareCode      ## the event text IS the link code (Discord interaction)
    ilsModalOnly     ## UI-only event; no identity is needed or minted

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

proc linkTargetFrom(gate: IdentityGatePort;
                    kind: ChannelKind;
                    text: string;
                    source: InboundLinkSource): Option[UserId] {.gcsafe.} =
  case source
  of ilsCommandText: linkTargetFor(gate, kind, text)
  of ilsBareCode:    gate.peekLinkCode(text.strip)
  of ilsNone, ilsModalOnly: none(UserId)

proc authorizeInbound*(sm: SessionManager;
                       gate: IdentityGatePort;
                       kind: ChannelKind;
                       rawId: string;
                       text: string;
                       linkSource = ilsCommandText): InboundAuthorization {.gcsafe.} =
  ## Single DM gate shared by callback-style channels.
  ##
  ## Known identities are checked against the allowlist. New identities are
  ## minted only under `DmPolicyOpen` or when the event carries a valid link
  ## code for an already-authorized UUID (the handler consumes the code and
  ## rewrites the mapping). A denied sender is never persisted.
  if linkSource == ilsModalOnly:
    ## UI-only event: no identity lookup, mint or state mutation.
    result.allowed = true
    return
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
    let target = linkTargetFrom(gate, kind, text, linkSource)
    if target.isSome and sm.allows(target.get):
      result.userId =
        if known.isSome: known.get
        else: gate.resolve(kind, rawId)
      result.identified = true
      result.allowed = true

  if not result.allowed and sm.dmPolicy == DmPolicyPairing and
     sm.pairingRequest != nil and linkSource == ilsCommandText:
    let pairing = decideCommandRequest(CommandRequest(channel: kind, text: text))
    if pairing.kind == cmdPair:
      ## The admin approves the request out-of-band; the sender stays denied
      ## until the CLI adds the minted UUID to the allowlist.
      let requested = sm.pairingRequest(kind, rawId)
      if requested.isErr:
        {.cast(gcsafe).}:
          gateLog.warn("pairing request failed for " & $kind & " " & rawId &
                       ": " & requested.error)

proc authorizeResolvedInbound*(sm: SessionManager;
                               gate: IdentityGatePort;
                               kind: ChannelKind;
                               userId: UserId;
                               text: string;
                               rawId = "";
                               linkSource = ilsCommandText): InboundAuthorization {.gcsafe.} =
  ## Variant for channels that already resolved the raw identity (Telegram
  ## `receive()` does this). The policy decision still lives here.
  result.userId = userId
  result.identified = true
  result.allowed = sm.allows(userId)
  if not result.allowed:
    if linkSource == ilsModalOnly:
      result.allowed = true
      return
    let target = linkTargetFrom(gate, kind, text, linkSource)
    if target.isSome and sm.allows(target.get):
      result.allowed = true
  if not result.allowed and sm.dmPolicy == DmPolicyPairing and
     sm.pairingRequest != nil and rawId.len > 0 and
     linkSource == ilsCommandText:
    let pairing = decideCommandRequest(CommandRequest(channel: kind, text: text))
    if pairing.kind == cmdPair:
      let requested = sm.pairingRequest(kind, rawId)
      if requested.isErr:
        {.cast(gcsafe).}:
          gateLog.warn("pairing request failed for " & $kind & " " & rawId &
                       ": " & requested.error)
