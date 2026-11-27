## IRC, the pure half (second round, front 1): reading a line (IRCv3 tags,
## prefix, command, parameters), registration with SASL PLAIN, what the bot
## answers, and replies cut into lines the server accepts. Formats from RFC
## 1459/2812 and the IRCv3 specs (message-tags, account-tag, sasl-3.1).

import std/[base64, options, strutils, unittest]
import donkey/domain/channels/irc_pure
import donkey/core/pipeops

proc runTests*() =
  suite "irc — reading a line":

    test "tags, prefix, command and the trailing parameter":
      let m = parseLine("@account=belle;time=2026-11-26T03:00:00Z :Belle!b@host PRIVMSG #donkey :donkey: resume isso").get
      check m.tags.tagValue("account") == "belle"
      check m.nick == "Belle" and m.command == "PRIVMSG"
      check m.params == @["#donkey", "donkey: resume isso"]

    test "a line without prefix or tags, and escaped tag values":
      let ping = parseLine("PING :irc.example.net").get
      check ping.command == "PING" and ping.params == @["irc.example.net"]
      check parseLine("@msg=a\\sb\\:c :x PRIVMSG y :z").get.tags.tagValue("msg") == "a b;c"
      check parseLine("").isNone

  suite "irc — what the bot answers":

    test "a private message from an account is answered, as is":
      let p = inboundPrivmsg(parseLine("@account=belle :Belle!b@h PRIVMSG donkey :oi, tudo bem?").get, "donkey").get
      check p.account == "belle" and p.nick == "Belle" and p.text == "oi, tudo bem?"
      check not p.isGroup and p.replyTo == "Belle"

    test "in a channel only when addressed by name, the address taken out":
      check inboundPrivmsg(parseLine("@account=belle :Belle!b@h PRIVMSG #donkey :bom dia").get, "donkey").isNone
      let p = inboundPrivmsg(parseLine("@account=belle :Belle!b@h PRIVMSG #donkey :Donkey, resume isso").get, "donkey").get
      check p.isGroup and p.channel == "#donkey" and p.text == "resume isso"
      check p.replyTo == "#donkey"
      check inboundPrivmsg(parseLine("@account=belle :Belle!b@h PRIVMSG #donkey :donkeyish: oi").get, "donkey").isNone

    test "without a services account nobody is answered: a nick proves nothing":
      check inboundPrivmsg(parseLine(":Belle!b@h PRIVMSG donkey :oi").get, "donkey").isNone
      check inboundPrivmsg(parseLine("@account=* :Belle!b@h PRIVMSG donkey :oi").get, "donkey").isNone

    test "notices, CTCP and the bot's own lines are not turns":
      check inboundPrivmsg(parseLine("@account=belle :Belle!b@h NOTICE donkey :oi").get, "donkey").isNone
      check inboundPrivmsg(parseLine("@account=belle :Belle!b@h PRIVMSG donkey :\x01VERSION\x01").get, "donkey").isNone
      check inboundPrivmsg(parseLine("@account=bot :donkey!d@h PRIVMSG donkey :eco").get, "donkey").isNone

  suite "irc — registering and talking":

    test "registration asks for the capabilities, then NICK and USER":
      let lines = registration("donkey", "Donkey bot")
      check lines[0] == "CAP LS 302"
      check "NICK donkey" in lines and "USER donkey 0 * :Donkey bot" in lines

    test "the capabilities requested: account-tag and message-tags, sasl with a password":
      check capRequest("multi-prefix sasl account-tag message-tags", usePassword = true) ==
        "CAP REQ :account-tag message-tags sasl"
      check capRequest("account-tag", usePassword = false) == "CAP REQ :account-tag"
      check capRequest("multi-prefix", usePassword = false) == ""

    test "SASL PLAIN carries the account and password, base64":
      check saslPlain("donkey", "s3nh4") == "AUTHENTICATE " & encode("donkey\0donkey\0s3nh4")

    test "PING is answered with PONG and the same token":
      check pongFor(parseLine("PING :abc123").get) == "PONG :abc123"

    test "a reply becomes PRIVMSG lines, one per text line, cut under the limit":
      let lines = privmsgLines("#donkey", "primeira\nsegunda\n\n" & "x".repeat(IrcTextBytes + 5))
      check lines[0] == "PRIVMSG #donkey :primeira"
      check lines[1] == "PRIVMSG #donkey :segunda"
      check lines.len == 4
      for l in lines:
        check l.len <= IrcTextBytes + "PRIVMSG #donkey :".len
        check '\r' notin l and '\n' notin l

    test "a reply never carries a line break or a NUL into the protocol":
      for l in privmsgLines("Belle", "a\rb\0c"):
        check '\r' notin l and '\0' notin l

  suite "irc — the registration conversation":

    proc feed(s: var IrcSession; raw: string): seq[string] =
      react(s, parseLine(raw).get)

    test "with a password: capabilities, SASL, then the end of negotiation":
      var s = newIrcSession("donkey", "s3nh4", @["#donkey", "#ops"])
      check feed(s, ":srv CAP * LS :multi-prefix sasl account-tag message-tags") ==
        @["CAP REQ :account-tag message-tags sasl"]
      check feed(s, ":srv CAP * ACK :account-tag message-tags sasl") == @["AUTHENTICATE PLAIN"]
      check feed(s, "AUTHENTICATE +") == @[saslPlain("donkey", "s3nh4")]
      check feed(s, ":srv 903 donkey :SASL authentication successful") == @["CAP END"]
      check s.accountTags

    test "the welcome joins the channels; PING gets PONG":
      var s = newIrcSession("donkey", "", @["#donkey", "#ops"])
      discard feed(s, ":srv CAP * LS :account-tag")
      check feed(s, ":srv CAP * ACK :account-tag") == @["CAP END"]
      check feed(s, ":srv 001 donkey :Welcome") == @["JOIN #donkey,#ops"]
      check s.registered
      check feed(s, "PING :t1") == @["PONG :t1"]

    test "a server without account-tag leaves the bot deaf, and says why":
      var s = newIrcSession("donkey", "", @[])
      check feed(s, ":srv CAP * LS :multi-prefix") == @["CAP END"]
      check not s.accountTags
      check s.problems.len == 1 and "account-tag" in s.problems[0]

    test "a refused SASL ends negotiation and is reported":
      var s = newIrcSession("donkey", "errada", @[])
      discard feed(s, ":srv CAP * LS :sasl account-tag")
      discard feed(s, ":srv CAP * ACK :account-tag sasl")
      discard feed(s, "AUTHENTICATE +")
      check feed(s, ":srv 904 donkey :SASL authentication failed") == @["CAP END"]
      check s.problems.len == 1 and "SASL" in s.problems[0]

    test "a nick in use is retried with an underscore, and answers to it":
      var s = newIrcSession("donkey", "", @[])
      check feed(s, ":srv 433 * donkey :Nickname is already in use") == @["NICK donkey_"]
      check s.nick == "donkey_"

  suite "irc — across a process (E12.3)":
    test "a PRIVMSG makes the round trip through the wire":
      let m = IrcPrivmsg(account: "ana", nick: "ana_", text: "oi\nolá", channel: "#d",
                         isGroup: true, replyTo: "#d")
      let back = privmsgFromWire(privmsgToWire(m))
      check back.isOk and back.get == m

    test "a payload that is not one is an error":
      check privmsgFromWire("{oops").isErr
      check privmsgFromWire("[]").isErr

when isMainModule:
  runTests()
