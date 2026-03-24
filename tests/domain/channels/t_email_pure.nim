## Tests for domain/channels/email_pure — pure RFC 2822 email parsing.
##
## All tests are deterministic: no I/O, no filesystem, no network.
## Covers: findHeader, parseEmail, toInbound, hasAttachment.
##
## Topology exercised:
##   |>    — raw |> parseEmail
##   |>->  — headers |>-> findHeader("From")

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/channels/email_pure
import donkey/domain/message

# ── helpers ───────────────────────────────────────────────────────────────────

proc makeRaw(headers: string; body: string = ""): string =
  headers & "\r\n\r\n" & body

proc makeRawLF(headers: string; body: string = ""): string =
  headers & "\n\n" & body

# ── findHeader ────────────────────────────────────────────────────────────────

suite "email_pure — findHeader":

  test "finds From header (CRLF)":
    let hdr = "From: alice@example.com\r\nSubject: hello"
    check (hdr |>-> findHeader("From")) == "alice@example.com"

  test "finds Subject header":
    let hdr = "From: alice@example.com\r\nSubject: Test Subject\r\nDate: Mon, 1 Jan 2024 00:00:00 +0000"
    check (hdr |>-> findHeader("Subject")) == "Test Subject"

  test "case-insensitive header match":
    let hdr = "FROM: bob@example.com\r\nSUBJECT: upper"
    check (hdr |>-> findHeader("from")) == "bob@example.com"
    check (hdr |>-> findHeader("FROM")) == "bob@example.com"

  test "returns empty string for absent header":
    let hdr = "Subject: test\r\nDate: now"
    check (hdr |>-> findHeader("From")) == ""

  test "handles LF-only line endings":
    let hdr = "From: lf@example.com\nSubject: lf-test"
    check (hdr |>-> findHeader("From")) == "lf@example.com"

  test "strips leading whitespace from value":
    let hdr = "Subject:   padded subject"
    check (hdr |>-> findHeader("Subject")) == "padded subject"

  test "handles Message-ID header":
    let hdr = "Message-ID: <abc123@mail.example.com>"
    check (hdr |>-> findHeader("Message-ID")) == "<abc123@mail.example.com>"

  test "handles empty header value":
    let hdr = "Subject: \r\nFrom: x@y.com"
    check (hdr |>-> findHeader("Subject")) == ""

  test "returns first occurrence when header repeats":
    let hdr = "X-Header: first\r\nX-Header: second"
    check (hdr |>-> findHeader("X-Header")) == "first"

# ── parseEmail ────────────────────────────────────────────────────────────────

suite "email_pure — parseEmail":

  test "parses minimal text/plain email":
    let raw = makeRaw(
      "From: alice@example.com\r\nSubject: Hello\r\nContent-Type: text/plain",
      "Hello world!"
    )
    let r = raw |> parseEmail
    check r.kind == emkText
    check r.fromAddr == "alice@example.com"
    check r.subject == "Hello"
    check r.body == "Hello world!"

  test "parses text/html email":
    let raw = makeRaw(
      "From: sender@example.com\r\nContent-Type: text/html",
      "<b>hi</b>"
    )
    let r = raw |> parseEmail
    check r.kind == emkHtml
    check r.body == "<b>hi</b>"

  test "defaults to text when Content-Type absent":
    let raw = makeRaw("From: x@example.com\r\nSubject: no ct")
    let r = raw |> parseEmail
    check r.kind == emkText

  test "emkUnknown on empty input":
    let r = "" |> parseEmail
    check r.kind == emkUnknown
    check r.fromAddr == ""
    check r.subject == ""

  test "extracts Message-ID":
    let raw = makeRaw(
      "From: a@b.com\r\nMessage-ID: <unique-id@example.com>",
      "body"
    )
    let r = raw |> parseEmail
    check r.messageId == "<unique-id@example.com>"

  test "extracts Date header":
    let raw = makeRaw(
      "From: a@b.com\r\nDate: Tue, 2 Jan 2024 12:00:00 +0000",
      ""
    )
    let r = raw |> parseEmail
    check r.date == "Tue, 2 Jan 2024 12:00:00 +0000"

  test "handles LF-only separators":
    let raw = makeRawLF("From: lf@example.com\nSubject: LF email", "LF body")
    let r = raw |> parseEmail
    check r.kind == emkText
    check r.fromAddr == "lf@example.com"
    check r.body == "LF body"

  test "body can be empty":
    let raw = makeRaw("From: a@b.com", "")
    let r = raw |> parseEmail
    check r.body == ""

  test "contentType field is populated":
    let raw = makeRaw("From: x@y.com\r\nContent-Type: text/plain; charset=utf-8")
    let r = raw |> parseEmail
    check "text/plain" in r.contentType

  test "pipeops |>-> works for From extraction":
    let raw = makeRaw("From: pipe@example.com\r\nSubject: pipe test", "body")
    let r = raw |> parseEmail
    check r.fromAddr == "pipe@example.com"

# ── toInbound ─────────────────────────────────────────────────────────────────

suite "email_pure — toInbound":

  test "maps email result to InboundMessage":
    let r = EmailParseResult(
      kind:      emkText,
      fromAddr:  "sender@example.com",
      messageId: "<msg-001@example.com>",
      body:      "Hello from email",
    )
    let uid = UserId("user-uuid-01")
    let msg = r.toInbound(uid)
    check msg.userId == uid
    check msg.channel == ckEmail
    check msg.channelId == "<msg-001@example.com>"
    check msg.text == "Hello from email"
    check msg.mediaUrl == ""

  test "channelId is Message-ID (used for dedup)":
    let r = EmailParseResult(kind: emkText, messageId: "<dedup-key@mail.com>")
    let msg = r.toInbound(UserId("u"))
    check msg.channelId == "<dedup-key@mail.com>"

  test "channelId is empty when Message-ID absent":
    let r = EmailParseResult(kind: emkText)
    let msg = r.toInbound(UserId("u"))
    check msg.channelId == ""

# ── hasAttachment ─────────────────────────────────────────────────────────────

suite "email_pure — hasAttachment":

  test "false for text/plain":
    let r = EmailParseResult(kind: emkText)
    check not r.hasAttachment

  test "false for text/html":
    let r = EmailParseResult(kind: emkHtml)
    check not r.hasAttachment

  test "true for unknown kind (future multipart support)":
    let r = EmailParseResult(kind: emkUnknown)
    check r.hasAttachment
