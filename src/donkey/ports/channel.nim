## ChannelPort — concept for messaging channels (Telegram, Discord, WeChat…).
##
## `c` is immutable: send and ack work on a value or ref.
## `vc` is mutable: receive may advance internal state (offset, buffer, etc.).
##
## Discord's send() uses a ref Table internally for DM channel caching, so it
## works fine with an immutable receiver despite mutating the cache through the ref.

import ../domain/message
import ../core/pipeops

type
  ChannelPort* = concept c, var vc
    c.send(OutboundMessage) is Result[void, string]
    vc.receive() is Result[seq[InboundMessage], string]
    c.ack(string)
