## ChannelCapabilityDescriptor — declarative capability contract per channel.
##
## Each channel declares which outbound operations it supports via a structured
## boolean contract.  This replaces the manual `unsupported*` patching that
## previously lived in outbound_builder.nim.

import ../core/types
import ../core/commands/command_surface

type
  ChannelCapabilityFlag* = enum
    cfSend              ## basic message send
    cfSendReturnId      ## send returning the created message id
    cfEditMessage       ## edit an existing message by id
    cfSendKeyboard      ## send message with inline keyboard
    cfEditKeyboard      ## edit keyboard of an existing message
    cfSetMessageReaction ## react to a message
    cfDownloadFile      ## download files/media from messages
    cfSendMedia         ## send media/files as messages
    cfSendVoice         ## send an audio file delivered as a voice note

  ChannelCapabilityDescriptor* = object
    send*:               bool
    sendReturnId*:       bool
    editMessage*:        bool
    sendKeyboard*:       bool
    editKeyboard*:       bool
    setMessageReaction*: bool
    downloadFile*:       bool
    sendMedia*:          bool
    sendVoice*:          bool
    configUi*:           bool  ## /config is answered with a button view
    interactiveMenus*:   bool  ## /menu is answered with a button view
    repliesToRequester*: bool
      ## Every reply is addressed to the requester (DM, open_id, openid), even
      ## for a command sent from a group, so no reply lands in a shared space.

  ChannelCapabilityRegistry* = array[ChannelKind, ChannelCapabilityDescriptor]

# ── registry ──────────────────────────────────────────────────────────────────
## One canonical registry — built at module init time.
## Keep this table in sync with what each adapter actually implements.

const
  BasicCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: false, editMessage: false,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false,
    downloadFile: false, sendMedia: false)

  SendOnlyCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: false, editMessage: false,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false,
    downloadFile: true, sendMedia: true)

  EmailCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: false, editMessage: false,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false,
    downloadFile: false, sendMedia: false)

  CliCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: true, editMessage: true,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false,
    downloadFile: false, sendMedia: false)

  ## Telegram is the only channel that delivers a local audio file as a voice
  ## note.
  TelegramCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: true, editMessage: true,
    sendKeyboard: true, editKeyboard: true, setMessageReaction: true,
    downloadFile: true, sendMedia: true, sendVoice: true,
    configUi: true, interactiveMenus: true)

  ## Discord and Slack runtimes answer /config and /menu with button views.
  DiscordCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: true, editMessage: true,
    sendKeyboard: true, editKeyboard: true, setMessageReaction: true,
    downloadFile: true, sendMedia: true,
    configUi: true, interactiveMenus: true)

  SlackCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: true, editMessage: true,
    sendKeyboard: true, editKeyboard: true, setMessageReaction: false,
    downloadFile: false, sendMedia: true,
    configUi: true, interactiveMenus: true)

  ## LINE: send-only. Reply/push accept plain text chunks; no ids, edits,
  ## keyboards, reactions, media or voice notes.
  LineCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: false, editMessage: false,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false,
    downloadFile: false, sendMedia: false, sendVoice: false)

  # Teams: text replies in the thread (Markdown); no edits or media yet
  # Mattermost: text posts in the thread; no edits or media yet
  ## Text only, in the thread: SMS, IRC, Google Chat (until E9 gives them
  ## attachments).
  TextOnlyCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: false, editMessage: false,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false,
    downloadFile: false, sendMedia: false, sendVoice: false)

  ## Mattermost: text and attachments both ways (E9.1).
  MattermostCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: false, editMessage: false,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false,
    downloadFile: true, sendMedia: true, sendVoice: false)

  TeamsCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: false, editMessage: false,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false,
    downloadFile: false, sendMedia: false, sendVoice: false)

  # QQ supports sendKeyboard but not editKeyboard
  QQCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: false, editMessage: false,
    sendKeyboard: true, editKeyboard: false, setMessageReaction: false,
    downloadFile: false, sendMedia: false)

  # Matrix: no keyboard support
  MatrixCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: true, editMessage: true,
    sendKeyboard: false, editKeyboard: false, setMessageReaction: false,
    downloadFile: true, sendMedia: false)

  # DingTalk: editKeyboard reuses editMessage (text-only) — treated as no editKeyboard
  DingTalkCapability = ChannelCapabilityDescriptor(
    send: true, sendReturnId: true, editMessage: true,
    sendKeyboard: true, editKeyboard: false, setMessageReaction: false,
    downloadFile: false, sendMedia: false)

proc channelCapabilityRegistry*(): ChannelCapabilityRegistry =
  result[ckTelegram]   = TelegramCapability
  result[ckDiscord]    = DiscordCapability
  result[ckWeCom]      = BasicCapability
  result[ckWeChat]     = BasicCapability
  result[ckQQ]         = QQCapability
  result[ckFeishu]     = BasicCapability
  result[ckSlack]      = SlackCapability
  result[ckWhatsApp]   = SendOnlyCapability
  result[ckSignal]     = SendOnlyCapability
  result[ckDingTalk]   = DingTalkCapability
  result[ckMatrix]     = MatrixCapability
  result[ckEmail]      = EmailCapability
  result[ckCli]        = CliCapability
  result[ckLine]       = LineCapability
  result[ckTeams]      = TeamsCapability
  result[ckMattermost] = MattermostCapability
  result[ckSms]        = TextOnlyCapability
  result[ckIrc]        = TextOnlyCapability
  result[ckGoogleChat] = TextOnlyCapability
  for kind in [ckWeCom, ckWeChat, ckFeishu, ckSlack, ckWhatsApp]:
    result[kind].repliesToRequester = true

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
  of cfDownloadFile:      caps.downloadFile
  of cfSendMedia:         caps.sendMedia
  of cfSendVoice:         caps.sendVoice

func commandCaps*(d: ChannelCapabilityDescriptor): CommandSurfaceCaps =
  CommandSurfaceCaps(configUi: d.configUi, interactiveMenus: d.interactiveMenus)

func commandCaps*(kind: ChannelKind): CommandSurfaceCaps =
  capability(kind).commandCaps
