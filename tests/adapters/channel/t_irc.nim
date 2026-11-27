## IRC connection and adapter (second round, front 1). A fake server on
## loopback (plain TCP: the daemon always uses TLS) checks the thread end to
## end: registration, SASL, joining, a message from an account reaching the
## queue, a reply going out, PING answered.

import std/[net, os, strutils, unittest]
import donkey/adapters/channel/irc
import donkey/adapters/identity/identity_resolver
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/infra/connection_state

proc waitFor(cond: proc(): bool; ms = 5_000): bool =
  var waited = 0
  while waited < ms:
    if cond(): return true
    sleep(20)
    waited += 20
  cond()

proc readUntil(c: Socket; needle: string; seen: var seq[string]): bool =
  for _ in 0 ..< 50:
    var line = ""
    try: line = c.recvLine(2_000)
    except TimeoutError: return false
    if line.len == 0: return false
    seen.add line
    if needle in line: return true
  false

proc runTests*() =
  suite "irc server setting":

    test "host, or host:port; 6697 by default":
      check parseIrcServer("irc.libera.chat").get == ("irc.libera.chat", 6697)
      check parseIrcServer("irc.example.net:7000").get == ("irc.example.net", 7000)
      check parseIrcServer("irc.example.net:x").isErr
      check parseIrcServer("").isErr

  suite "irc adapter":
    setup:
      while tryTakeOutLine()[0]: discard

    test "a reply becomes PRIVMSG lines for the connection thread":
      let dir = getTempDir() / "donkey_irc_ad"
      removeDir(dir); createDir(dir)
      let a = newIrcAdapter(true, dir / "ids.tsv", dir / "nicks.json")
      check a.send(OutboundMessage(channel: ckIrc, replyTo: "#donkey", text: "a\nb")).isOk
      check tryTakeOutLine() == (true, "PRIVMSG #donkey :a")
      check tryTakeOutLine() == (true, "PRIVMSG #donkey :b")

    test "without a target, the account's last nick; an injected target is refused":
      let dir = getTempDir() / "donkey_irc_ad2"
      removeDir(dir); createDir(dir)
      let a = newIrcAdapter(true, dir / "ids.tsv", dir / "nicks.json")
      let uid = a.resolver.resolve(ckIrc, "belle")
      check a.send(OutboundMessage(userId: uid, channel: ckIrc, text: "x")).isErr
      check a.rememberNick("belle", "Belle_").isOk
      check a.send(OutboundMessage(userId: uid, channel: ckIrc, text: "lembrete")).isOk
      check tryTakeOutLine() == (true, "PRIVMSG Belle_ :lembrete")
      check a.send(OutboundMessage(channel: ckIrc, replyTo: "x\r\nQUIT", text: "oi")).isErr
      check a.send(OutboundMessage(channel: ckIrc, replyTo: ":x", text: "oi")).isErr
      check a.send(OutboundMessage(channel: ckIrc, replyTo: "@x", text: "oi")).isErr
      check a.send(OutboundMessage(channel: ckIrc, replyTo: "a:b", text: "oi")).isErr
      let b = newIrcAdapter(true, dir / "ids.tsv", dir / "nicks.json")
      check b.send(OutboundMessage(userId: uid, channel: ckIrc, text: "depois")).isOk

    test "not configured: every send says why":
      let r = newIrcAdapter(false, "", "").send(
        OutboundMessage(channel: ckIrc, replyTo: "#x", text: "oi"))
      check r.isErr and "IRC_SERVER" in r.error

  suite "irc connection":

    test "registers, logs in, joins, hands over a message and sends the reply":
      while tryRecvIrc()[0]: discard
      while tryTakeOutLine()[0]: discard
      var server = newSocket()
      server.setSockOpt(OptReuseAddr, true)
      server.bindAddr(Port(0), "127.0.0.1")
      server.listen()
      let port = server.getLocalAddr()[1]
      check startIrc(IrcSettings(host: "127.0.0.1", port: int(port), nick: "donkey",
                                 realName: "Donkey", password: "s3nh4",
                                 channels: @["#donkey"], tls: false),
                     newLogger("test.irc", lvlError)).isOk
      var client: Socket
      server.accept(client)
      var seen: seq[string]
      check readUntil(client, "USER donkey", seen)
      check "CAP LS 302" in seen and "NICK donkey" in seen
      client.send(":srv CAP * LS :sasl account-tag\r\n")
      check readUntil(client, "CAP REQ", seen)
      client.send(":srv CAP * ACK :account-tag sasl\r\n")
      check readUntil(client, "AUTHENTICATE PLAIN", seen)
      client.send("AUTHENTICATE +\r\n")
      check readUntil(client, "AUTHENTICATE ", seen)
      client.send(":srv 903 donkey :ok\r\n")
      check readUntil(client, "CAP END", seen)
      client.send(":srv 001 donkey :Welcome\r\n")
      check readUntil(client, "JOIN #donkey", seen)
      check waitFor(proc(): bool = connectionCounts(ckIrc) == (running: 1, connected: 1))
      client.send("@account=belle :Belle!b@h PRIVMSG donkey :oi, tudo bem?\r\n")
      var got: IrcPrivmsg
      check waitFor(proc(): bool =
        let (has, m) = tryRecvIrc()
        if has: got = m
        has)
      check got.account == "belle" and got.text == "oi, tudo bem?"
      check pushOutLine("PRIVMSG Belle :tudo ótimo")
      check readUntil(client, "PRIVMSG Belle :tudo ótimo", seen)
      client.send("PING :xyz\r\n")
      check readUntil(client, "PONG :xyz", seen)
      stopIrc()
      check connectionCounts(ckIrc) == (running: 0, connected: 0)
      client.close()
      server.close()

  suite "irc — as its own process (E12.3)":
    test "the daemon's side: the child's events into the inbound queue, outbound lines to the child":
      let m = IrcPrivmsg(account: "ana", nick: "ana", text: "oi", replyTo: "ana")
      ircProcessSink(privmsgToWire(m))
      let (has, got) = tryRecvIrc()
      check has and got == m
      ircProcessSink("{not json")              ## dropped, not raised
      check not tryRecvIrc()[0]
      check pushOutLine("PRIVMSG ana :olá")
      check ircProcessSource() == (true, "PRIVMSG ana :olá")

    test "the child's side: the connection's events out, outbound lines into its queue":
      let m = IrcPrivmsg(account: "bia", nick: "bia", text: "e aí", replyTo: "bia")
      check pushIrc(m)
      check ircWorkerEvent() == (true, privmsgToWire(m))
      ircWorkerOut("PRIVMSG bia :tudo")
      check tryTakeOutLine() == (true, "PRIVMSG bia :tudo")

    test "IRC as a process: the command is this binary's channel-worker":
      check ircWorkerSpec("/usr/bin/donkey").args == @["channel-worker", "irc"]
      check ircWorkerSpec("/usr/bin/donkey").channel == ckIrc

when isMainModule:
  runTests()
