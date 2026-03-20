## FeishuAdapter — ChannelPort stub for Feishu/Lark WebSocket gateway.
##
## Connects via Feishu WebSocket long-connection gateway.
## Receives events and sends messages via Feishu Open API.
##
## Status: stub — gateway not yet implemented.
## Events are returned via tryRecvEvent (non-blocking).

import ../../core/pipeops
import ../../domain/message
import ../identity/identity_resolver

type
  FeishuEvent* = object
    msgType*: string   ## "text", "image", etc.
    openId*:  string   ## Feishu user open_id
    msgId*:   string
    content*: string

  FeishuAdapter* = object
    appId*:     string
    appSecret*: string
    resolver*:  IdentityResolver
    events:     seq[FeishuEvent]

proc newFeishuAdapter*(appId, appSecret: string;
                        identityPath: string): FeishuAdapter =
  FeishuAdapter(
    appId:     appId,
    appSecret: appSecret,
    resolver:  newIdentityResolver(identityPath),
    events:    @[],
  )

proc startGateway*(a: var FeishuAdapter) =
  ## Connects to Feishu WebSocket gateway in a background thread.
  ## Stub: no-op until gateway is implemented.
  discard

proc tryRecvEvent*(a: var FeishuAdapter): (bool, FeishuEvent) =
  ## Non-blocking dequeue of the next gateway event.
  if a.events.len == 0:
    return (false, FeishuEvent())
  let ev = a.events[0]
  a.events.delete(0)
  (true, ev)

proc send*(a: var FeishuAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message via Feishu Open API.
  ## Stub: no-op.
  ok()
