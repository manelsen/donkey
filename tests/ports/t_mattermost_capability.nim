## Mattermost's capability (second round, front 1): text replies only, like
## Teams; the outbound port sends through the adapter and refuses the rest.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/domain/message
import donkey/core/types
import donkey/ports/channel_capability
import donkey/adapters/channel/outbound_builder
import donkey/adapters/channel/mattermost
import donkey/adapters/channel/sms
import donkey/adapters/channel/irc
import donkey/adapters/channel/google_chat

proc runTests*() =
  suite "mattermost capability":

    test "the registry says: send, attachments both ways (E9.1)":
      let c = channelCapabilityRegistry()[ckMattermost]
      check c.send and not c.editMessage and not c.sendKeyboard
      check c.sendMedia and c.downloadFile

    test "the channel's name round-trips":
      check $ckMattermost == "mattermost"

    test "without an adapter the port is unsupported; with one it sends":
      check mattermostOutboundPort(nil).send(
        OutboundMessage(channel: ckMattermost, text: "oi")).isErr
      var a = newMattermostAdapter("https://chat.example.com", "", "", "")
      let r = mattermostOutboundPort(addr a).send(
        OutboundMessage(channel: ckMattermost, replyTo: "c", text: "oi"))
      check r.isErr and "MATTERMOST_TOKEN" in r.error   ## reached the adapter

  suite "sms capability":

    test "the registry says: send only; the port reaches the adapter":
      let c = channelCapabilityRegistry()[ckSms]
      check c.send and not c.editMessage and not c.sendMedia
      check $ckSms == "sms"
      check smsOutboundPort(nil).send(OutboundMessage(channel: ckSms, text: "oi")).isErr
      var a = newSmsAdapter("", "", "", "")
      let r = smsOutboundPort(addr a).send(OutboundMessage(channel: ckSms, replyTo: "+1", text: "oi"))
      check r.isErr and "TWILIO" in r.error

  suite "irc capability":

    test "the registry says: send only; the port reaches the adapter":
      let c = channelCapabilityRegistry()[ckIrc]
      check c.send and not c.editMessage and not c.sendMedia
      check $ckIrc == "irc"
      check ircOutboundPort(nil).send(OutboundMessage(channel: ckIrc, text: "oi")).isErr
      var a = newIrcAdapter(false, "", "")
      let r = ircOutboundPort(addr a).send(OutboundMessage(channel: ckIrc, replyTo: "#x", text: "oi"))
      check r.isErr and "IRC_SERVER" in r.error

  suite "google chat capability":

    test "the registry says: send text, receive attachments (E9.2); the port reaches the adapter":
      let c = channelCapabilityRegistry()[ckGoogleChat]
      check c.send and not c.editMessage and not c.sendMedia
      check c.downloadFile   ## an app cannot upload (user auth only), but it can download
      check googleChatOutboundPort(nil).downloadFile("AbC").isErr
      check $ckGoogleChat == "google-chat"
      check googleChatOutboundPort(nil).send(OutboundMessage(channel: ckGoogleChat, text: "oi")).isErr
      var a = newGoogleChatAdapter("", "", "")
      let r = googleChatOutboundPort(addr a).send(
        OutboundMessage(channel: ckGoogleChat, replyTo: "spaces/S1", text: "oi"))
      check r.isErr and "GOOGLE_CHAT_SERVICE_ACCOUNT" in r.error

when isMainModule:
  runTests()
