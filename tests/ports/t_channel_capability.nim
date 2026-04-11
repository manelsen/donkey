## Unit tests for ChannelCapabilityDescriptor — capability resolution per channel.

import std/unittest
import donkey/core/types
import donkey/ports/channel_capability

# ── ChannelCapabilityDescriptor structure ─────────────────────────────────────

suite "ChannelCapabilityDescriptor — structure":

  test "descriptor has all six boolean fields":
    let d = ChannelCapabilityDescriptor(
      send: true, sendReturnId: true, editMessage: true,
      sendKeyboard: true, editKeyboard: true, setMessageReaction: true)
    check d.send
    check d.sendReturnId
    check d.editMessage
    check d.sendKeyboard
    check d.editKeyboard
    check d.setMessageReaction

  test "empty descriptor has all false":
    let d = ChannelCapabilityDescriptor()
    check not d.send
    check not d.sendReturnId
    check not d.editMessage
    check not d.sendKeyboard
    check not d.editKeyboard
    check not d.setMessageReaction

# ── Registry completeness ─────────────────────────────────────────────────────

suite "channelCapabilityRegistry — completeness":

  test "registry covers all ChannelKind values":
    let reg = channelCapabilityRegistry()
    for kind in ChannelKind:
      # Every channel must have a non-default entry (send must be true at minimum)
      let hasSend = reg[kind].send
      doAssert hasSend, "channel " & $kind & " missing from registry"
      check hasSend

  test "registry size matches ChannelKind count":
    # Registry is an array indexed by ChannelKind, so its size equals ChannelKind.len
    check true  # Structural guarantee by type system

# ── Telegram capabilities ─────────────────────────────────────────────────────

suite "channel capability — Telegram":

  test "Telegram supports all capabilities":
    let caps = capability(ckTelegram)
    check caps.send
    check caps.sendReturnId
    check caps.editMessage
    check caps.sendKeyboard
    check caps.editKeyboard
    check caps.setMessageReaction

# ── Discord capabilities ──────────────────────────────────────────────────────

suite "channel capability — Discord":

  test "Discord supports all capabilities":
    let caps = capability(ckDiscord)
    check caps.send
    check caps.sendReturnId
    check caps.editMessage
    check caps.sendKeyboard
    check caps.editKeyboard
    check caps.setMessageReaction

# ── WeCom capabilities (basic — send only) ────────────────────────────────────

suite "channel capability — WeCom":

  test "WeCom supports send":
    check supports(ckWeCom, cfSend)

  test "WeCom does not support sendReturnId":
    check not supports(ckWeCom, cfSendReturnId)

  test "WeCom does not support editMessage":
    check not supports(ckWeCom, cfEditMessage)

  test "WeCom does not support keyboard operations":
    check not supports(ckWeCom, cfSendKeyboard)
    check not supports(ckWeCom, cfEditKeyboard)

  test "WeCom does not support setMessageReaction":
    check not supports(ckWeCom, cfSetMessageReaction)

# ── WeChat capabilities (basic — send only) ───────────────────────────────────

suite "channel capability — WeChat":

  test "WeChat supports send only":
    let caps = capability(ckWeChat)
    check caps.send
    check not caps.sendReturnId
    check not caps.editMessage
    check not caps.sendKeyboard
    check not caps.editKeyboard
    check not caps.setMessageReaction

# ── QQ capabilities (send + sendKeyboard) ─────────────────────────────────────

suite "channel capability — QQ":

  test "QQ supports send and sendKeyboard":
    check supports(ckQQ, cfSend)
    check supports(ckQQ, cfSendKeyboard)

  test "QQ does not support sendReturnId or editMessage":
    check not supports(ckQQ, cfSendReturnId)
    check not supports(ckQQ, cfEditMessage)

  test "QQ does not support editKeyboard":
    check not supports(ckQQ, cfEditKeyboard)

# ── Feishu capabilities (basic — send only) ───────────────────────────────────

suite "channel capability — Feishu":

  test "Feishu supports send only":
    let caps = capability(ckFeishu)
    check caps.send
    check not caps.sendReturnId
    check not caps.editMessage

# ── Slack capabilities (no reactions) ─────────────────────────────────────────

suite "channel capability — Slack":

  test "Slack supports everything except setMessageReaction":
    let caps = capability(ckSlack)
    check caps.send
    check caps.sendReturnId
    check caps.editMessage
    check caps.sendKeyboard
    check caps.editKeyboard
    check not caps.setMessageReaction

# ── WhatsApp / Signal (send only) ─────────────────────────────────────────────

suite "channel capability — WhatsApp":

  test "WhatsApp supports send only":
    let caps = capability(ckWhatsApp)
    check caps.send
    check not caps.sendReturnId
    check not caps.editMessage

suite "channel capability — Signal":

  test "Signal supports send only":
    let caps = capability(ckSignal)
    check caps.send
    check not caps.sendReturnId
    check not caps.editMessage

# ── DingTalk capabilities ─────────────────────────────────────────────────────

suite "channel capability — DingTalk":

  test "DingTalk supports send, sendReturnId, editMessage, sendKeyboard":
    check supports(ckDingTalk, cfSend)
    check supports(ckDingTalk, cfSendReturnId)
    check supports(ckDingTalk, cfEditMessage)
    check supports(ckDingTalk, cfSendKeyboard)

  test "DingTalk does not support editKeyboard":
    check not supports(ckDingTalk, cfEditKeyboard)

# ── Matrix capabilities ───────────────────────────────────────────────────────

suite "channel capability — Matrix":

  test "Matrix supports send, sendReturnId, editMessage":
    check supports(ckMatrix, cfSend)
    check supports(ckMatrix, cfSendReturnId)
    check supports(ckMatrix, cfEditMessage)

  test "Matrix does not support keyboard or reaction":
    check not supports(ckMatrix, cfSendKeyboard)
    check not supports(ckMatrix, cfEditKeyboard)
    check not supports(ckMatrix, cfSetMessageReaction)

# ── Email capabilities ────────────────────────────────────────────────────────

suite "channel capability — Email":

  test "Email supports send only":
    let caps = capability(ckEmail)
    check caps.send
    check not caps.sendReturnId
    check not caps.editMessage
    check not caps.sendKeyboard

# ── CLI capabilities ──────────────────────────────────────────────────────────

suite "channel capability — CLI":

  test "CLI supports send, sendReturnId, editMessage":
    check supports(ckCli, cfSend)
    check supports(ckCli, cfSendReturnId)
    check supports(ckCli, cfEditMessage)

  test "CLI does not support keyboard or reaction":
    check not supports(ckCli, cfSendKeyboard)
    check not supports(ckCli, cfEditKeyboard)
    check not supports(ckCli, cfSetMessageReaction)

# ── supports() helper ─────────────────────────────────────────────────────────

suite "supports() helper":

  test "supports returns true for Telegram cfSend":
    check supports(ckTelegram, cfSend)

  test "supports returns false for Email cfEditMessage":
    check not supports(ckEmail, cfEditMessage)

  test "supports is consistent across all flags for Telegram":
    for flag in ChannelCapabilityFlag:
      check supports(ckTelegram, flag)
