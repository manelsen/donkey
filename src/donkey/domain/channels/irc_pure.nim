## irc_pure — IRC, the pure half (second round, front 1).
##
## A line is `[@tags] [:prefix] COMMAND params [:trailing]` (RFC 1459/2812,
## IRCv3 message-tags). A nick proves nothing on IRC, so a person is the
## services account the server vouches for in the `account` tag (IRCv3
## account-tag); a line without one is never a turn. The bot logs in with
## SASL PLAIN (sasl-3.1) when it has a password. In a channel it answers only
## when addressed by name (`donkey: …` or `donkey, …`).

import std/[base64, options, strutils]
from std/unicode import runes, toUTF8

const
  IrcTextBytes* = 400
    ## A line is at most 512 bytes with CRLF; the server prepends our prefix
    ## when relaying, so the text keeps a wide margin.

type
  IrcTag* = tuple[key, value: string]

  IrcLine* = object
    tags*:    seq[IrcTag]
    nick*:    string   ## from the prefix; empty for server lines
    command*: string
    params*:  seq[string]

  IrcPrivmsg* = object
    account*, nick*, text*: string
    channel*: string   ## empty for a private message
    isGroup*: bool
    replyTo*: string   ## the channel, or the sender's nick

func unescapeTag(v: string): string =
  var i = 0
  while i < v.len:
    if v[i] == '\\' and i + 1 < v.len:
      case v[i + 1]
      of ':': result.add ';'
      of 's': result.add ' '
      of 'r': result.add '\r'
      of 'n': result.add '\n'
      else: result.add v[i + 1]
      i += 2
    else:
      result.add v[i]
      inc i

func tagValue*(tags: seq[IrcTag]; key: string): string =
  for t in tags:
    if t.key == key: return t.value

func parseLine*(raw: string): Option[IrcLine] =
  var s = raw.strip(leading = false, chars = {'\r', '\n'})
  if s.len == 0: return none(IrcLine)
  var line = IrcLine()
  if s[0] == '@':
    let sp = s.find(' ')
    if sp < 0: return none(IrcLine)
    for part in s[1 ..< sp].split(';'):
      if part.len == 0: continue
      let eq = part.find('=')
      if eq < 0: line.tags.add (part, "")
      else: line.tags.add (part[0 ..< eq], unescapeTag(part[eq + 1 .. ^1]))
    s = s[sp + 1 .. ^1].strip(trailing = false)
  if s.len > 0 and s[0] == ':':
    let sp = s.find(' ')
    if sp < 0: return none(IrcLine)
    let prefix = s[1 ..< sp]
    let bang = prefix.find('!')
    line.nick = if bang >= 0: prefix[0 ..< bang] else: prefix
    s = s[sp + 1 .. ^1].strip(trailing = false)
  let trailingAt = s.find(" :")
  var head = s
  var trailing = none(string)
  if trailingAt >= 0:
    head = s[0 ..< trailingAt]
    trailing = some(s[trailingAt + 2 .. ^1])
  let words = head.splitWhitespace()
  if words.len == 0: return none(IrcLine)
  line.command = words[0].toUpperAscii
  line.params = words[1 .. ^1]
  if trailing.isSome: line.params.add trailing.get
  some(line)

func addressed(text, nick: string): Option[string] =
  ## The rest of `nick: …` / `nick, …` (any case), or none.
  let lower = text.toLowerAscii
  let n = nick.toLowerAscii
  if not lower.startsWith(n) or text.len <= n.len: return none(string)
  if text[n.len] notin {':', ','}: return none(string)
  some(text[n.len + 1 .. ^1].strip)

func inboundPrivmsg*(line: IrcLine; botNick: string): Option[IrcPrivmsg] =
  ## A PRIVMSG the bot should answer, from someone the server knows by
  ## account; none for anything else.
  if line.command != "PRIVMSG" or line.params.len < 2: return none(IrcPrivmsg)
  let account = line.tags.tagValue("account")
  if account.len == 0 or account == "*": return none(IrcPrivmsg)
  if line.nick.len == 0 or cmpIgnoreCase(line.nick, botNick) == 0: return none(IrcPrivmsg)
  let target = line.params[0]
  let text = line.params[1]
  if text.len == 0 or text[0] == '\x01': return none(IrcPrivmsg)   ## CTCP
  if target.len > 0 and target[0] in {'#', '&', '!', '+'}:
    let rest = addressed(text, botNick)
    if rest.isNone or rest.get.len == 0: return none(IrcPrivmsg)
    some(IrcPrivmsg(account: account, nick: line.nick, text: rest.get,
                    channel: target, isGroup: true, replyTo: target))
  else:
    if text.strip.len == 0: return none(IrcPrivmsg)
    some(IrcPrivmsg(account: account, nick: line.nick, text: text,
                    replyTo: line.nick))

func registration*(nick, realName: string): seq[string] =
  @["CAP LS 302", "NICK " & nick, "USER " & nick & " 0 * :" & realName]

func capRequest*(offered: string; usePassword: bool): string =
  ## What to ask for among what the server offers (values after `=` ignored).
  var have: seq[string]
  for c in offered.splitWhitespace:
    have.add c.split('=')[0]
  var want: seq[string]
  for c in ["account-tag", "message-tags"]:
    if c in have: want.add c
  if usePassword and "sasl" in have: want.add "sasl"
  if want.len == 0: "" else: "CAP REQ :" & want.join(" ")

func saslPlain*(account, password: string): string =
  "AUTHENTICATE " & encode(account & "\0" & account & "\0" & password)

func pongFor*(ping: IrcLine): string =
  "PONG :" & (if ping.params.len > 0: ping.params[^1] else: "")

func cutUtf8(text: string; maxBytes: int): seq[string] =
  ## Pieces of at most `maxBytes`, never splitting a character.
  var piece = ""
  for r in text.runes:
    let s = r.toUTF8
    if piece.len + s.len > maxBytes:
      result.add piece
      piece = ""
    piece.add s
  if piece.len > 0: result.add piece

func privmsgLines*(target, text: string): seq[string] =
  ## One PRIVMSG per text line (blank lines dropped), each cut under the
  ## limit; CR and NUL never reach the protocol.
  var clean = newStringOfCap(text.len)
  for c in text:
    if c notin {'\r', '\0'}: clean.add c
  for raw in clean.split('\n'):
    if raw.strip.len == 0: continue
    for piece in cutUtf8(raw, IrcTextBytes):
      result.add "PRIVMSG " & target & " :" & piece

# ── The registration conversation ─────────────────────────────────────────────

type
  IrcSession* = object
    ## What the connection knows of itself; fed every line by `react`.
    nick*:        string
    password:     string
    channels:     seq[string]
    accountTags*: bool   ## the server vouches for accounts: people can be answered
    registered*:  bool   ## 001 seen
    problems*:    seq[string]   ## for the caller to log, then clear

func newIrcSession*(nick, password: string; channels: seq[string]): IrcSession =
  IrcSession(nick: nick, password: password, channels: channels)

func react*(s: var IrcSession; line: IrcLine): seq[string] =
  ## The lines to send back to one line from the server.
  case line.command
  of "PING":
    result.add pongFor(line)
  of "CAP":
    let sub = if line.params.len >= 2: line.params[1].toUpperAscii else: ""
    let list = if line.params.len >= 3: line.params[^1] else: ""
    case sub
    of "LS":
      let req = capRequest(list, s.password.len > 0)
      if "account-tag" notin req:
        s.problems.add "the server does not offer account-tag: nobody can be identified, so nobody is answered"
      result.add(if req.len > 0: req else: "CAP END")
    of "ACK":
      let acked = list.splitWhitespace
      s.accountTags = "account-tag" in acked
      if "sasl" in acked: result.add "AUTHENTICATE PLAIN"
      else: result.add "CAP END"
    of "NAK":
      s.problems.add "the server refused the capabilities: " & list
      result.add "CAP END"
    else: discard
  of "AUTHENTICATE":
    if line.params.len > 0 and line.params[0] == "+":
      result.add saslPlain(s.nick, s.password)
  of "903":
    result.add "CAP END"
  of "902", "904", "905", "906", "908":
    s.problems.add "SASL login failed (" & line.command & "); going on without it"
    result.add "CAP END"
  of "001":
    s.registered = true
    if line.params.len > 0 and line.params[0].len > 0: s.nick = line.params[0]
    if s.channels.len > 0: result.add "JOIN " & s.channels.join(",")
  of "433":
    s.nick = s.nick & "_"
    result.add "NICK " & s.nick
  else: discard
