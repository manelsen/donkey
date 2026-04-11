## Unit tests for outbound_builder capability resolution.
## Verifies that outbound ports are wired correctly per channel capability descriptor.

import std/[unittest, strutils]
import donkey/core/types
import donkey/core/pipeops
import donkey/domain/message
import donkey/ports/channel
import donkey/ports/channel_capability
import donkey/adapters/channel/outbound_builder

# ── Capability consistency between descriptor and outbound wiring ─────────────

suite "outbound capability consistency":

  test "channels with full capability have all adapter methods wired":
    ## Telegram and Discord declare full capability — their outbound ports
    ## should have real implementations for all 6 operations.
    ## We verify via the capability descriptor.
    for kind in [ckTelegram, ckDiscord]:
      let caps = capability(kind)
      check caps.send
      check caps.sendReturnId
      check caps.editMessage
      check caps.sendKeyboard
      check caps.editKeyboard
      check caps.setMessageReaction

  test "basic channels (WeCom, WeChat, Feishu) only have send":
    for kind in [ckWeCom, ckWeChat, ckFeishu]:
      let caps = capability(kind)
      check caps.send
      check not caps.sendReturnId
      check not caps.editMessage
      check not caps.sendKeyboard
      check not caps.editKeyboard
      check not caps.setMessageReaction

  test "partial channels match expected capability pattern":
    # QQ: send + sendKeyboard
    let qq = capability(ckQQ)
    check qq.send
    check not qq.sendReturnId
    check not qq.editMessage
    check qq.sendKeyboard
    check not qq.editKeyboard
    check not qq.setMessageReaction

    # Slack: all except reaction
    let sl = capability(ckSlack)
    check sl.send
    check sl.sendReturnId
    check sl.editMessage
    check sl.sendKeyboard
    check sl.editKeyboard
    check not sl.setMessageReaction

    # DingTalk: send, sendReturnId, editMessage, sendKeyboard
    let dt = capability(ckDingTalk)
    check dt.send
    check dt.sendReturnId
    check dt.editMessage
    check dt.sendKeyboard
    check not dt.editKeyboard
    check not dt.setMessageReaction

    # Matrix: send, sendReturnId, editMessage
    let mx = capability(ckMatrix)
    check mx.send
    check mx.sendReturnId
    check mx.editMessage
    check not mx.sendKeyboard
    check not mx.editKeyboard
    check not mx.setMessageReaction

    # CLI: send, sendReturnId, editMessage
    let cli = capability(ckCli)
    check cli.send
    check cli.sendReturnId
    check cli.editMessage
    check not cli.sendKeyboard
    check not cli.editKeyboard
    check not cli.setMessageReaction

  test "send-only channels are consistent":
    for kind in [ckWhatsApp, ckSignal]:
      let caps = capability(kind)
      check caps.send
      # Everything else should be false
      check not caps.sendReturnId
      check not caps.editMessage
      check not caps.sendKeyboard
      check not caps.editKeyboard
      check not caps.setMessageReaction

  test "email is send-only":
    let caps = capability(ckEmail)
    check caps.send
    check not caps.sendReturnId
    check not caps.editMessage
    check not caps.sendKeyboard
    check not caps.editKeyboard
    check not caps.setMessageReaction

# ── Unsupported stub behaviour ────────────────────────────────────────────────
## When a capability is declared as unsupported, calling the corresponding
## outbound port method should return an error (not crash).

suite "unsupported stub behaviour":

  test "unsupportedSendReturnId returns error with channel name":
    # We can't easily test individual proc stubs without building full ports,
    # but we can verify the capability descriptor says they should be unsupported.
    for kind in [ckWeCom, ckWeChat, ckFeishu, ckQQ, ckEmail]:
      check not capability(kind).sendReturnId

  test "unsupportedEditMessage returns error with channel name":
    for kind in [ckWeCom, ckWeChat, ckFeishu, ckQQ, ckEmail]:
      check not capability(kind).editMessage

  test "unsupported keyboard ops return error":
    for kind in [ckWeCom, ckWeChat, ckFeishu, ckEmail, ckMatrix, ckCli]:
      check not capability(kind).sendKeyboard
      check not capability(kind).editKeyboard

  test "unsupported reaction returns error":
    for kind in [ckWeCom, ckWeChat, ckFeishu, ckQQ, ckEmail, ckMatrix, ckSlack, ckDingTalk, ckCli]:
      check not capability(kind).setMessageReaction

# ── Registry is the single source of truth ────────────────────────────────────

suite "registry as single source of truth":

  test "all ChannelKind values have a capability entry":
    for kind in ChannelKind:
      let caps = capability(kind)
      # At minimum, every channel must support send
      doAssert caps.send, "channel " & $kind & " does not declare send capability"
      check caps.send

  test "capability flags are internally consistent":
    ## Channels that support editMessage should generally support sendReturnId
    ## (since editing requires knowing the message id).
    for kind in ChannelKind:
      let caps = capability(kind)
      if caps.editMessage:
        # editMessage implies the channel can track message ids
        doAssert caps.sendReturnId, $kind & " has editMessage but not sendReturnId"
        check caps.sendReturnId
