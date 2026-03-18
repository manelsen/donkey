## QQAdapter — ChannelPort stub for QQ Official Bot (OneBot / QQ Open Platform).
##
## Status: MAPPED (not yet implemented).
##
## QQ Official Bot uses QQ Open Platform's official API (not OneBot v11):
##   - AppID + AppSecret → access_token (OAuth 2.0 client_credentials)
##   - WebSocket gateway for receiving events (guild, group, private)
##   - REST API for sending messages (text, markdown, keyboard)
##   - Event types: MESSAGE_CREATE, DIRECT_MESSAGE_CREATE, GROUP_AT_MESSAGE_CREATE
##
## Implementation notes (when promoted to functional):
##   - Guild (频道), group (群), and private (私信) are distinct routing contexts
##   - Message reference field required for replies in guild/group channels
##   - Content-based filtering by Tencent (sensitive word blocking in guild)
##   - Media: image/audio require upload to QQ CDN before sending
##
## Reference: docs/blueprint/LobsterAI/src/main/im/qqGateway_skel.ts

import ../../core/types

type
  QQAdapter* = object
    appId*:     string
    appSecret*: string
    apiBase*:   string  ## override for testing

proc newQQAdapter*(appId, appSecret: string;
                   apiBase = ""): QQAdapter =
  QQAdapter(appId: appId, appSecret: appSecret, apiBase: apiBase)
