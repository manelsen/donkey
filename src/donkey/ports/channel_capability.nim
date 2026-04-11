## ChannelCapabilityDescriptor — declarative capability contract per channel.
##
## Each channel declares which outbound operations it supports via a structured
## boolean contract.  This replaces the manual `unsupported*` patching that
## previously lived in outbound_builder.nim.

import ../core/types

type
  ChannelCapabilityFlag* = enum
    cfSend              ## basic message send
    cfSendReturnId      ## send returning the created message id
    cfEditMessage       ## edit an existing message by id
    cfSendKeyboard      ## send message with inline keyboard
    cfEditKeyboard      ## edit keyboard of an existing message
    cfSetMessageReaction ## react to a message

  ChannelCapabilityDescriptor* = object
    send*:               bool
    sendReturnId*:       bool
    editMessage*:        bool
    sendKeyboard*:       bool
    editKeyboard*:       bool
    setMessageReaction*: bool

  ChannelCapabilityRegistry* = array[ChannelKind, ChannelCapabilityDescriptor]

# ── registry ──────────────────────────────────────────────────────────────────
## One canonical registry — built at module init time.
## Keep this table in sync with what each adapter actually implements.

const
  FullCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: true, editMessage: true,
    sendKeyboard: true, editKeyboard: true, setMessageReaction: true)

  NoReactionCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: true, editMessage: true,
    sendKeyboard: true, editKeyboard: true, setMessageReaction: false)

  BasicCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: false, editMessage: false,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false)

  SendOnlyCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: false, editMessage: false,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false)

  EmailCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: false, editMessage: false,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false)

  CliCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: true, editMessage: true,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false)

  # QQ supports sendKeyboard but not editKeyboard
  QQCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: false, editMessage: false,
    sendKeyboard: true, editKeyboard: false, setMessageReaction: false)

  # Matrix: no keyboard support
  MatrixCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: true, editMessage: true,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false)

  # DingTalk: editKeyboard reuses editMessage (text-only) — treated as no editKeyboard
  DingTalkCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: true, editMessage: true,
    sendKeyboard: true, editKeyboard: false, setMessageReaction: false)

proc channelCapabilityRegistry*(): ChannelCapabilityRegistry =
  result[ckTelegram]   = FullCapability
  result[ckDiscord]    = FullCapability
  result[ckWeCom]      = BasicCapability
  result[ckWeChat]     = BasicCapability
  result[ckQQ]         = QQCapability
  result[ckFeishu]     = BasicCapability
  result[ckSlack]      = NoReactionCapability
  result[ckWhatsApp]   = SendOnlyCapability
  result[ckSignal]     = SendOnlyCapability
  result[ckDingTalk]   = DingTalkCapability
  result[ckMatrix]     = MatrixCapability
  result[ckEmail]      = EmailCapability
  result[ckCli]        = CliCapability

# ── lookup helpers ────────────────────────────────────────────────────────────

func capability*(kind: ChannelKind): ChannelCapabilityDescriptor =
  ## Returns the capability descriptor for a single channel kind.
  let reg = channelCapabilityRegistry()
  reg[kind]

func supports*(kind: ChannelKind; flag: ChannelCapabilityFlag): bool =
  ## Checks whether `kind` supports the given capability flag.
  let caps = capability(kind)
  case flag
  of cfSend:              caps.send
  of cfSendReturnId:      caps.sendReturnId
  of cfEditMessage:       caps.editMessage
  of cfSendKeyboard:      caps.sendKeyboard
  of cfEditKeyboard:      caps.editKeyboard
  of cfSetMessageReaction: caps.setMessageReaction
