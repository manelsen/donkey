## EmailAdapter unit tests.
## No network connections are made — tests cover adapter construction,
## identity resolution, email_pure parsing, and SMTP message building.

import std/[os, strutils, unittest]
import donkey/adapters/channel/email
import donkey/adapters/identity/identity_resolver
import donkey/core/types
import donkey/domain/channels/email_pure

# ── IdentityResolver (Email) ───────────────────────────────────────────────────

suite "IdentityResolver (Email)":

  test "creates new UUID for unknown email address":
    let path = getTempDir() / "donkey_test_ids_em1.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r   = newIdentityResolver(path)
    let uid = r.resolve(ckEmail, "alice@example.com")
    check ($uid).len == 36

  test "same email returns same UserId":
    let path = getTempDir() / "donkey_test_ids_em2.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckEmail, "alice@example.com")
    let u2 = r.resolve(ckEmail, "alice@example.com")
    check u1 == u2

  test "different emails get different UserIds":
    let path = getTempDir() / "donkey_test_ids_em3.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckEmail, "alice@example.com")
    let u2 = r.resolve(ckEmail, "bob@example.com")
    check u1 != u2

  test "identity persists across resolver instances":
    let path = getTempDir() / "donkey_test_ids_em4.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid1 = newIdentityResolver(path).resolve(ckEmail, "carol@example.com")
    let uid2 = newIdentityResolver(path).resolve(ckEmail, "carol@example.com")
    check uid1 == uid2

# ── EmailAdapter construction ──────────────────────────────────────────────────

suite "EmailAdapter construction":

  test "imapHost is stored":
    let a = newEmailAdapter("imap.example.com", "smtp.example.com",
                            "user@example.com", "secret",
                            "/tmp/ids_emc1.tsv")
    check a.imapHost == "imap.example.com"

  test "smtpHost is stored":
    let a = newEmailAdapter("imap.example.com", "smtp.example.com",
                            "user@example.com", "secret",
                            "/tmp/ids_emc2.tsv")
    check a.smtpHost == "smtp.example.com"

  test "user is stored":
    let a = newEmailAdapter("imap.example.com", "smtp.example.com",
                            "user@example.com", "secret",
                            "/tmp/ids_emc3.tsv")
    check a.user == "user@example.com"

  test "password is stored":
    let a = newEmailAdapter("imap.example.com", "smtp.example.com",
                            "user@example.com", "mypassword",
                            "/tmp/ids_emc4.tsv")
    check a.password == "mypassword"

  test "default imapPort is 993":
    let a = newEmailAdapter("imap.example.com", "smtp.example.com",
                            "user@example.com", "secret",
                            "/tmp/ids_emc5.tsv")
    check a.imapPort == 993

  test "default smtpPort is 587":
    let a = newEmailAdapter("imap.example.com", "smtp.example.com",
                            "user@example.com", "secret",
                            "/tmp/ids_emc6.tsv")
    check a.smtpPort == 587

  test "custom ports are stored":
    let a = newEmailAdapter("imap.example.com", "smtp.example.com",
                            "user@example.com", "secret",
                            "/tmp/ids_emc7.tsv",
                            imapPort = 143, smtpPort = 465)
    check a.imapPort == 143
    check a.smtpPort == 465

  test "fromAddr defaults to user when not given":
    let a = newEmailAdapter("imap.example.com", "smtp.example.com",
                            "user@example.com", "secret",
                            "/tmp/ids_emc8.tsv")
    check a.fromAddr == "user@example.com"

  test "explicit fromAddr is stored":
    let a = newEmailAdapter("imap.example.com", "smtp.example.com",
                            "user@example.com", "secret",
                            "/tmp/ids_emc9.tsv",
                            fromAddr = "Bot Name <bot@example.com>")
    check a.fromAddr == "Bot Name <bot@example.com>"

  test "startTls defaults to true":
    let a = newEmailAdapter("imap.example.com", "smtp.example.com",
                            "user@example.com", "secret",
                            "/tmp/ids_emca.tsv")
    check a.startTls == true

  test "startTls can be set to false":
    let a = newEmailAdapter("imap.example.com", "smtp.example.com",
                            "user@example.com", "secret",
                            "/tmp/ids_emcb.tsv", startTls = false)
    check a.startTls == false

# ── email_pure.parseEmail ──────────────────────────────────────────────────────

suite "email_pure.parseEmail":

  test "parses From header":
    let raw = "From: alice@example.com\r\nSubject: Hi\r\n\r\nHello"
    let r = parseEmail(raw)
    check r.fromAddr == "alice@example.com"

  test "parses Subject header":
    let raw = "From: alice@example.com\r\nSubject: Test Subject\r\n\r\nBody"
    let r = parseEmail(raw)
    check r.subject == "Test Subject"

  test "parses Message-ID header":
    let raw = "From: a@b.com\r\nMessage-ID: <msg-001@example.com>\r\n\r\nBody"
    let r = parseEmail(raw)
    check r.messageId == "<msg-001@example.com>"

  test "parses Date header":
    let raw = "From: a@b.com\r\nDate: Mon, 01 Jan 2024 12:00:00 +0000\r\n\r\nBody"
    let r = parseEmail(raw)
    check r.date == "Mon, 01 Jan 2024 12:00:00 +0000"

  test "parses plain text body":
    let raw = "From: a@b.com\r\nContent-Type: text/plain\r\n\r\nHello World"
    let r = parseEmail(raw)
    check r.body == "Hello World"
    check r.kind == emkText

  test "identifies text/html kind":
    let raw = "From: a@b.com\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<b>Hi</b>"
    let r = parseEmail(raw)
    check r.kind == emkHtml

  test "defaults to emkText when Content-Type absent":
    let raw = "From: a@b.com\r\nSubject: No CT\r\n\r\nPlain body"
    let r = parseEmail(raw)
    check r.kind == emkText

  test "handles LF-only line endings":
    let raw = "From: alice@example.com\nSubject: LF Test\n\nBody text"
    let r = parseEmail(raw)
    check r.fromAddr == "alice@example.com"
    check r.subject  == "LF Test"
    check r.body     == "Body text"

  test "empty input returns emkUnknown":
    let r = parseEmail("")
    check r.kind == emkUnknown

  test "body contains multi-line text":
    let raw = "From: a@b.com\r\n\r\nLine one\r\nLine two\r\nLine three"
    let r = parseEmail(raw)
    check "Line one" in r.body
    check "Line two" in r.body

  test "missing From returns empty fromAddr":
    let raw = "Subject: No From\r\n\r\nBody"
    let r = parseEmail(raw)
    check r.fromAddr == ""

# ── email_pure.findHeader ──────────────────────────────────────────────────────

suite "email_pure.findHeader":

  test "finds header by name":
    let headers = "From: alice@example.com\r\nSubject: Hello"
    check findHeader("From", headers) == "alice@example.com"

  test "case-insensitive header name":
    let headers = "FROM: alice@example.com\r\nSubject: Hello"
    check findHeader("from", headers) == "alice@example.com"

  test "returns empty for absent header":
    let headers = "Subject: Hello\r\nDate: Today"
    check findHeader("From", headers) == ""

  test "trims leading whitespace from value":
    let headers = "From:   alice@example.com"
    check findHeader("From", headers) == "alice@example.com"

  test "handles LF-only separators":
    let headers = "From: alice@example.com\nSubject: Test"
    check findHeader("Subject", headers) == "Test"

# ── email_pure.toInbound ───────────────────────────────────────────────────────

suite "email_pure.toInbound":

  test "converts result to InboundMessage":
    let raw = "From: alice@example.com\r\nMessage-ID: <id-001@test>\r\n\r\nHello"
    let r   = parseEmail(raw)
    let uid = UserId("test-uuid-em-0001")
    let msg = r.toInbound(uid)
    check msg.userId    == uid
    check msg.channel   == ckEmail
    check msg.channelId == "<id-001@test>"
    check msg.text      == "Hello"
    check msg.mediaUrl  == ""

  test "body maps to text field":
    let raw = "From: alice@example.com\r\n\r\nAgent response body"
    let r   = parseEmail(raw)
    let msg = r.toInbound(UserId("uid-text"))
    check msg.text == "Agent response body"

  test "hasAttachment is false for text/plain":
    let r = parseEmail("From: a@b.com\r\nContent-Type: text/plain\r\n\r\nBody")
    check not r.hasAttachment

  test "hasAttachment is false for text/html":
    let r = parseEmail("From: a@b.com\r\nContent-Type: text/html\r\n\r\n<b>Hi</b>")
    check not r.hasAttachment

# ── buildSmtpMessage ───────────────────────────────────────────────────────────

suite "buildSmtpMessage":

  test "includes From header":
    let msg = buildSmtpMessage("bot@example.com", "user@example.com",
                               "Re: Test", "Hello")
    check "From: bot@example.com" in msg

  test "includes To header":
    let msg = buildSmtpMessage("bot@example.com", "user@example.com",
                               "Re: Test", "Hello")
    check "To: user@example.com" in msg

  test "includes Subject header":
    let msg = buildSmtpMessage("bot@example.com", "user@example.com",
                               "Re: My Subject", "Body")
    check "Subject: Re: My Subject" in msg

  test "includes body after blank line":
    let msg = buildSmtpMessage("bot@example.com", "user@example.com",
                               "Re: Test", "The body text")
    check "The body text" in msg

  test "strips newlines from subject (prevents header injection)":
    let msg = buildSmtpMessage("bot@example.com", "user@example.com",
                               "Injected\r\nBcc: evil@example.com", "Body")
    ## \r\n stripped — no new header injected; Bcc: appears inline in subject
    check "\r\nBcc:" notin msg
    check "\nBcc:" notin msg

  test "includes Content-Type header":
    let msg = buildSmtpMessage("bot@example.com", "user@example.com",
                               "Test", "Body")
    check "Content-Type: text/plain" in msg
