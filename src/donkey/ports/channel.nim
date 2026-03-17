## ChannelPort — concept for messaging channels (Telegram, Discord, WeChat…).
##
## Adapters: TelegramAdapter (F1), DiscordAdapter (F5), WeComAdapter (F8).
## Each adapter absorbs its own auth, polling/webhook, and message format quirks.

import ../domain/message

type
  ChannelPort* = concept c
    c.send(OutboundMessage)
    ## Delivers a message to the channel. Raises on unrecoverable error.

    c.receive() is seq[InboundMessage]
    ## Returns zero or more new inbound messages.
    ## Long-polling adapters block until timeout; webhook adapters drain a queue.

    c.ack(string)
    ## Acknowledges a message by its channel-specific id (channelId).
    ## No-op for channels that do not require explicit ack.
