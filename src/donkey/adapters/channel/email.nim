## EmailAdapter — ChannelPort for email via IMAP (polling) and SMTP (sending).
##
## Receiving: polls an IMAP inbox over SSL (port 993) for UNSEEN messages.
##   The daemon calls receive() in its polling loop.
##   Each UNSEEN message is fetched as raw RFC822, parsed, identity-resolved,
##   and marked \Seen before being returned.
##
## Sending: SMTP with STARTTLS (port 587) or implicit TLS (port 465).
##   Implemented directly over std/net to avoid external package dependency.
##
## Routing convention:
##   rawId = From header value (sender email address)
##   reverseChannel(userId, ckEmail) → sender's email address for replies.
##
## IMAP protocol flow:
##   LOGIN → SELECT INBOX → SEARCH UNSEEN → FETCH RFC822 → STORE +FLAGS \Seen
##   → LOGOUT
##
## SMTP protocol flow (STARTTLS, port 587):
##   EHLO → STARTTLS → EHLO → AUTH LOGIN → MAIL FROM → RCPT TO → DATA → QUIT
##
## Topology (pipeops):
##   |>   — raw |> parseEmail
##   >>=  — (reserved for future chained IMAP command sequences)

import std/[net, strutils, base64]
import std/posix
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/email_pure
import ../identity/identity_resolver

export identity_resolver

const
  ImapDefaultPort* = 993   ## IMAP over SSL (implicit TLS)
  SmtpDefaultPort* = 587   ## SMTP + STARTTLS
  EmailMaxChars*   = 16000 ## Conservative plain-text body size limit per chunk

# ── IMAP session ───────────────────────────────────────────────────────────────

type ImapSession = object
  sock:   Socket
  ctx:    SslContext
  tagSeq: int

proc nextTag(s: var ImapSession): string =
  inc s.tagSeq
  "D" & $s.tagSeq

proc imapSend(s: ImapSession; line: string): Result[void, string] =
  try:
    s.sock.send(line & "\r\n")
    ok()
  except CatchableError as e:
    err("IMAP send: " & e.msg)

proc imapReadResponse(s: ImapSession; tag: string): Result[seq[string], string] =
  ## Reads IMAP response lines until the tagged completion line (OK/NO/BAD).
  ## Handles IMAP string literals {n} by reading exactly n bytes.
  try:
    var lines: seq[string]
    while true:
      let line = s.sock.recvLine()
      # Detect IMAP literal: line ends with {n}
      if line.len > 2 and line[^1] == '}':
        let bracePos = line.rfind('{')
        if bracePos >= 0:
          let sizeStr = line[bracePos + 1 ..< line.len - 1]
          var litSize = 0
          try: litSize = parseInt(sizeStr)
          except ValueError: discard
          lines.add(line)
          # Read exactly litSize bytes
          if litSize > 0:
            var buf = ""
            var remaining = litSize
            while remaining > 0:
              var chunk = newString(min(remaining, 4096))
              let n = s.sock.recv(chunk, min(remaining, 4096))
              if n <= 0: return err("IMAP: connection closed reading literal")
              buf.add(chunk[0 ..< n])
              remaining -= n
            lines.add(buf)
          continue
      lines.add(line)
      if line.startsWith(tag & " OK") or
         line.startsWith(tag & " NO") or
         line.startsWith(tag & " BAD"):
        break
    ok(lines)
  except CatchableError as e:
    err("IMAP response: " & e.msg)

proc imapCmd(s: var ImapSession; cmd: string): Result[seq[string], string] =
  let tag = s.nextTag()
  ? s.imapSend(tag & " " & cmd)
  s.imapReadResponse(tag)

proc imapExec(s: var ImapSession; cmd: string): Result[void, string] =
  ## Runs an IMAP command and discards the response lines. Returns err on failure.
  discard ? s.imapCmd(cmd)
  ok()

proc imapClose(s: ImapSession) =
  try: s.sock.close()
  except IOError: discard

proc applySocketTimeouts(sock: Socket; seconds: int = 15) =
  ## Bounds blocking IMAP/SMTP reads so a stuck server cannot freeze the daemon.
  var tv: Timeval
  tv.tv_sec = Time(seconds)
  tv.tv_usec = Suseconds(0)
  discard setsockopt(sock.getFd, SOL_SOCKET, SO_RCVTIMEO, addr tv, SockLen(sizeof(tv)))
  discard setsockopt(sock.getFd, SOL_SOCKET, SO_SNDTIMEO, addr tv, SockLen(sizeof(tv)))

proc newImapSession(host: string; port: int): Result[ImapSession, string] =
  try:
    let ctx  = newContext(verifyMode = CVerifyPeer)
    let sock = newSocket(Domain.AF_INET, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
    ctx.wrapSocket(sock)
    sock.connect(host, Port(port))
    applySocketTimeouts(sock)
    discard sock.recvLine()  ## read server greeting
    ok(ImapSession(sock: sock, ctx: ctx, tagSeq: 0))
  except CatchableError as e:
    err("IMAP connect to " & host & ":" & $port & ": " & e.msg)

# ── IMAP response parsers ──────────────────────────────────────────────────────

proc parseSearchNums(lines: seq[string]): seq[int]
                    {.gcsafe, raises: [].} =
  ## Extracts sequence numbers from an IMAP SEARCH response.
  ## Example: "* SEARCH 1 2 5"  →  @[1, 2, 5]
  for line in lines:
    if line.startsWith("* SEARCH"):
      let rest = line[8 .. ^1].strip()
      if rest.len == 0: return
      for p in rest.splitWhitespace():
        try: result.add(parseInt(p))
        except ValueError: discard

proc extractFetchLiteral(lines: seq[string]): string =
  ## Returns the literal body from an IMAP FETCH response.
  ## After readResponse the literal content is stored as lines[1].
  if lines.len >= 2:
    return lines[1]
  ""

# ── SMTP client ────────────────────────────────────────────────────────────────

type SmtpSession = object
  sock: Socket
  ctx:  SslContext

proc smtpRecvLine(s: SmtpSession): Result[string, string] =
  try:
    ok(s.sock.recvLine())
  except CatchableError as e:
    err("SMTP recv: " & e.msg)

proc smtpSend(s: SmtpSession; line: string): Result[void, string] =
  try:
    s.sock.send(line & "\r\n")
    ok()
  except CatchableError as e:
    err("SMTP send: " & e.msg)

proc smtpReadUntilOk(s: SmtpSession): Result[string, string] =
  ## Reads multi-line SMTP response; returns last line. Fails on 4xx/5xx.
  var last = ""
  while true:
    let line = ? s.smtpRecvLine()
    last = line
    if line.len >= 4 and line[3] == ' ':
      let code = line[0 ..< 3]
      if code[0] in {'4', '5'}:
        return err("SMTP error: " & line)
      break
    elif line.len >= 4 and line[3] == '-':
      continue  ## multi-line, keep reading
    else:
      break
  ok(last)

proc smtpCheckOk(s: SmtpSession): Result[void, string] =
  ## Reads an SMTP response and returns ok() or err(). Discards response text.
  discard ? s.smtpReadUntilOk()
  ok()

proc smtpCmd(s: SmtpSession; cmd: string): Result[void, string] =
  ## Sends `cmd` and waits for a success response. Returns err on 4xx/5xx.
  ? s.smtpSend(cmd)
  s.smtpCheckOk()

proc smtpClose(s: SmtpSession) =
  try:
    discard s.smtpSend("QUIT")
    s.sock.close()
  except IOError: discard

proc newSmtpSession(host: string; port: int;
                    startTls: bool): Result[SmtpSession, string] =
  try:
    let ctx  = newContext(verifyMode = CVerifyPeer)
    let sock = newSocket(Domain.AF_INET, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
    if not startTls:
      ## Implicit TLS (port 465): wrap before connect
      ctx.wrapSocket(sock)
    sock.connect(host, Port(port))
    applySocketTimeouts(sock)
    let s = SmtpSession(sock: sock, ctx: ctx)
    ? s.smtpCheckOk()  ## read server greeting
    if startTls:
      ? s.smtpCmd("EHLO donkey")
      ? s.smtpCmd("STARTTLS")
      ctx.wrapConnectedSocket(sock, handshakeAsClient)
    ? s.smtpCmd("EHLO donkey")
    ok(s)
  except CatchableError as e:
    err("SMTP connect to " & host & ":" & $port & ": " & e.msg)

proc smtpAuth(s: SmtpSession; user, password: string): Result[void, string] =
  ? s.smtpCmd("AUTH LOGIN")
  ? s.smtpCmd(encode(user))
  ? s.smtpCmd(encode(password))
  ok()

proc smtpSendMail(s: SmtpSession; fromAddr, toAddr, msg: string): Result[void, string] =
  ? s.smtpCmd("MAIL FROM:<" & fromAddr & ">")
  ? s.smtpCmd("RCPT TO:<" & toAddr & ">")
  ? s.smtpCmd("DATA")
  ? s.smtpSend(msg)
  ? s.smtpSend(".")
  s.smtpCheckOk()

# ── EmailAdapter ───────────────────────────────────────────────────────────────

type
  EmailAdapter* = object
    imapHost*:   string  ## IMAP server hostname
    imapPort*:   int     ## IMAP port (default 993 for SSL)
    smtpHost*:   string  ## SMTP server hostname
    smtpPort*:   int     ## SMTP port (default 587 for STARTTLS)
    user*:       string  ## IMAP/SMTP username (usually the email address)
    password*:   string  ## IMAP/SMTP password or app password
    fromAddr*:   string  ## Envelope From address for outbound mail
    startTls*:   bool    ## SMTP: use STARTTLS (true for port 587)
    resolver*:   IdentityResolver

# ── Outbound helpers ───────────────────────────────────────────────────────────

func buildSmtpMessage*(fromAddr, toAddr, subject, body: string): string =
  ## Builds a minimal RFC 2822 message suitable for SMTP DATA.
  let safeSubject = subject.replace("\r", "").replace("\n", " ")
  "From: " & fromAddr & "\r\n" &
  "To: "   & toAddr   & "\r\n" &
  "Subject: " & safeSubject & "\r\n" &
  "Content-Type: text/plain; charset=utf-8\r\n\r\n" & body

proc sendSmtp(a: EmailAdapter; toAddr, subject, body: string): Result[void, string] =
  var s = ? newSmtpSession(a.smtpHost, a.smtpPort, a.startTls)
  defer: s.smtpClose()
  ? s.smtpAuth(a.user, a.password)
  let msg = buildSmtpMessage(a.fromAddr, toAddr, subject, body)
  s.smtpSendMail(a.fromAddr, toAddr, msg)

# ── Inbound polling ────────────────────────────────────────────────────────────

proc pollInbox*(a: EmailAdapter): Result[seq[InboundMessage], string] =
  ## Connects to IMAP, fetches UNSEEN messages, marks them \Seen, and
  ## returns resolved InboundMessages.
  var s = ? newImapSession(a.imapHost, a.imapPort)
  defer: s.imapClose()

  let loginResp = ? s.imapCmd("LOGIN \"" & a.user & "\" \"" & a.password & "\"")
  if loginResp.len > 0 and ("NO" in loginResp[^1] or "BAD" in loginResp[^1]):
    return err("IMAP LOGIN failed: " & loginResp[^1])

  ? s.imapExec("SELECT INBOX")

  let searchResp = ? s.imapCmd("SEARCH UNSEEN")
  let msgNums    = searchResp |> parseSearchNums

  var msgs: seq[InboundMessage]
  for num in msgNums:
    let fetchResp = ? s.imapCmd("FETCH " & $num & " RFC822")
    let raw       = fetchResp |> extractFetchLiteral
    if raw.len == 0: continue
    let parsed = raw |> parseEmail
    if parsed.fromAddr.len == 0: continue
    let uid = a.resolver.resolve(ckEmail, parsed.fromAddr)
    msgs.add(parsed.toInbound(uid))
    discard s.imapCmd("STORE " & $num & " +FLAGS (\\Seen)")

  discard s.imapCmd("LOGOUT")
  ok(msgs)

# ── ChannelPort methods ────────────────────────────────────────────────────────

proc receive*(a: var EmailAdapter): Result[seq[InboundMessage], string] =
  ## Polls IMAP inbox and returns new InboundMessages.
  a.pollInbox()

proc send*(a: EmailAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a reply email to the address resolved from the identity store.
  let toAddr = a.resolver.reverseChannel(msg.userId, ckEmail)
  if toAddr.len == 0:
    return err("EmailAdapter.send: no email address for user " & $msg.userId)
  for chunk in splitChunks(msg.text, EmailMaxChars):
    ? a.sendSmtp(toAddr, "Re: Donkey", chunk)
  ok()

proc sendReturnId*(a: EmailAdapter; msg: OutboundMessage): Result[string, string] =
  ## Sends and returns "" — email has no server-assigned id at send time.
  ? a.send(msg)
  ok("")

proc editMessage*(a: EmailAdapter; userId: UserId;
                  msgId, text: string): Result[void, string] =
  ## Email does not support editing; returns ok() silently.
  discard userId; discard msgId; discard text
  ok()

proc ack*(a: EmailAdapter; msgId: string) =
  ## No-op — IMAP messages are marked \Seen during pollInbox.
  discard

# ── Constructor ───────────────────────────────────────────────────────────────

proc newEmailAdapter*(imapHost, smtpHost, user, password: string;
                      identityPath: string;
                      fromAddr  = "";
                      imapPort  = ImapDefaultPort;
                      smtpPort  = SmtpDefaultPort;
                      startTls  = true): EmailAdapter =
  let resolvedFrom = if fromAddr.len > 0: fromAddr else: user
  EmailAdapter(
    imapHost:  imapHost,
    imapPort:  imapPort,
    smtpHost:  smtpHost,
    smtpPort:  smtpPort,
    user:      user,
    password:  password,
    fromAddr:  resolvedFrom,
    startTls:  startTls,
    resolver:  newIdentityResolver(identityPath),
  )
