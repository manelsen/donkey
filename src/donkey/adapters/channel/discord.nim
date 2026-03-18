## DiscordAdapter — ChannelPort stub for Discord gateway.
##
## Connects via Discord WebSocket gateway in a background thread.
## Supports slash commands (/continue pairing) and regular messages.
##
## Status: stub — gateway connectivity not yet implemented.
## Events are returned via tryRecvEvent (non-blocking).

import std/[json, os]
import chronos/asyncsync
import ../../core/pipeops
import ../../domain/message
import ../identity/identity_resolver

type
  DiscordEventKind* = enum
    deMessage      ## Regular message in a channel/DM
    deInteraction  ## Slash command interaction (/continue <code>)

  DiscordEvent* = object
    kind*:             DiscordEventKind
    messageId*:        string
    discordUserId*:    string   ## Discord snowflake user ID (as string)
    content*:          string
    interactionId*:    string
    interactionToken*: string

  DiscordAdapter* = object
    token*:    string
    resolver*: IdentityResolver
    events:    seq[DiscordEvent]   ## internal buffer (filled by gateway thread)

proc newDiscordAdapter*(token: string; identityPath: string): DiscordAdapter =
  DiscordAdapter(
    token:    token,
    resolver: newIdentityResolver(identityPath),
    events:   @[],
  )

proc startGateway*(a: var DiscordAdapter) =
  ## Connects to Discord WebSocket gateway in a background thread.
  ## Stub: no-op until gateway is implemented.
  discard

proc getAppId*(a: var DiscordAdapter): Result[string, string] =
  ## Fetches the application ID via GET /users/@me.
  ## Stub: returns empty string.
  ok("")

proc registerSlashCommands*(a: var DiscordAdapter;
                             appId: string): Result[void, string] =
  ## Registers slash commands for this application.
  ## Stub: no-op.
  ok()

proc tryRecvEvent*(a: var DiscordAdapter): (bool, DiscordEvent) =
  ## Non-blocking dequeue of the next gateway event.
  if a.events.len == 0:
    return (false, DiscordEvent())
  let ev = a.events[0]
  a.events.delete(0)
  (true, ev)

proc send*(a: DiscordAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message to a Discord channel.
  ## Stub: no-op.
  ok()

proc sendReturnId*(a: DiscordAdapter;
                   msg: OutboundMessage): Result[string, string] =
  ## Sends a message and returns the Discord message snowflake ID.
  ## Stub: returns empty string.
  ok("")

proc editMessage*(a: DiscordAdapter; userId: UserId;
                  messageId, text: string): Result[void, string] =
  ## Edits an existing Discord message in place (for streaming).
  ## Stub: no-op.
  ok()

proc sendInteractionResponse*(a: DiscordAdapter;
                               interactionId, interactionToken,
                               text: string): Result[void, string] =
  ## Responds to a slash command interaction.
  ## Stub: no-op.
  ok()
