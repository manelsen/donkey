## WeChatAdapter — ChannelPort stub for WeChat Official Account.
##
## Status: MAPPED (not yet implemented).
##
## WeChat Official Account API requires:
##   - OAuth 2.0 for user identity (openid)
##   - Webhook callback (same SHA-1 signature as WeCom — token, ts, nonce)
##   - POST /cgi-bin/message/custom/send to reply (access token auth)
##   - 48-hour customer service window restriction (cannot initiate outside window)
##
## Implementation notes (when promoted to functional):
##   - Share signature verification with WeComAdapter (same algorithm)
##   - Identity: openid per appid (distinct from WeCom corpid namespace)
##   - Rate limit: 500 000 sends/day per Official Account
##   - Template messages for proactive push outside service window

import ../../core/types

type
  WeChatAdapter* = object
    appId*:     string
    appSecret*: string
    token*:     string  ## webhook verification token
    apiBase*:   string  ## override for testing

proc newWeChatAdapter*(appId, appSecret, token: string;
                       apiBase = ""): WeChatAdapter =
  WeChatAdapter(appId: appId, appSecret: appSecret,
                token: token, apiBase: apiBase)
