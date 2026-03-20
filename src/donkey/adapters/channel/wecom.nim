## WeComAdapter — ChannelPort stub for WeCom (企业微信) webhook.
##
## Receives messages via HTTP webhook; sends via WeCom API.
##
## Status: stub — webhook server not yet implemented.
## Events are returned via tryRecvEvent (non-blocking).

import std/net
import ../../core/pipeops
import ../../domain/message
import ../identity/identity_resolver

type
  WeComEvent* = object
    msgType*:  string   ## "text", "image", etc.
    fromUser*: string   ## WeCom user ID
    msgId*:    string
    content*:  string

  WeComAdapter* = object
    corpId*:       string
    corpSecret*:   string
    callbackToken*: string
    agentId*:      int
    resolver*:     IdentityResolver
    events:        seq[WeComEvent]

proc newWeComAdapter*(corpId, corpSecret, callbackToken: string;
                      agentId: int; identityPath: string): WeComAdapter =
  WeComAdapter(
    corpId:        corpId,
    corpSecret:    corpSecret,
    callbackToken: callbackToken,
    agentId:       agentId,
    resolver:      newIdentityResolver(identityPath),
    events:        @[],
  )

proc startWebhook*(a: var WeComAdapter; port: Port) =
  ## Starts HTTP webhook listener on the given port.
  ## Stub: no-op until webhook server is implemented.
  discard

proc tryRecvEvent*(a: var WeComAdapter): (bool, WeComEvent) =
  ## Non-blocking dequeue of the next webhook event.
  if a.events.len == 0:
    return (false, WeComEvent())
  let ev = a.events[0]
  a.events.delete(0)
  (true, ev)

proc send*(a: var WeComAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message via WeCom API.
  ## Stub: no-op.
  ok()
