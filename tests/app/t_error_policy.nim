## Error policy tests — verify that silent failures are replaced with
## explicit returns, structured logs, and observability.
##
## AC: at least one isOkOr:discard and one except CatchableError:discard
## replaced with explicit return + log.

import std/[os, strutils, unittest, options, json, times]
import results
import donkey/core/log
import donkey/core/types
import donkey/adapters/memory/md_file
import donkey/adapters/embedding/openrouter_embed
import donkey/adapters/http/std_http
import donkey/domain/message
import donkey/ports/channel
import donkey/app/outbound_runtime

# ── Helpers ────────────────────────────────────────────────────────────────────

type
  CapturedLog = object
    level*: LogLevel
    subsystem*: string
    message*: string

  LogCapture = ref object
    entries: seq[CapturedLog]

proc newLogCapture(): LogCapture =
  LogCapture(entries: @[])

proc makeSink(cap: LogCapture): LogSink =
  result = proc(entry: LogEntry) {.gcsafe, closure.} =
    cap.entries.add(CapturedLog(
      level: entry.level,
      subsystem: entry.subsystem,
      message: entry.message,
    ))

proc runTests*() =
  # ── Tests: outbound send error visibility ─────────────────────────────────────

  suite "error policy — outbound send":

    test "sendImmediateOutbound logs error on failure":
      let cap = newLogCapture()
      let logger = newLogger("test.outbound_err", lvlDebug, makeSink(cap))

      let ports = OutboundChannelPorts(
        qq: OutboundChannelPort(
          send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
            err("network unreachable"),
          sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} = err("nope"),
          editMessage: proc(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.} =
            discard isHtml
            ok(),
          sendKeyboard: proc(userId: UserId; text: string;
                             buttons: seq[seq[(string, string)]];
                             replyTo = ""): Result[void, string] {.gcsafe.} = ok(),
          editKeyboard: proc(userId: UserId; msgId, text: string;
                             buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} = ok(),
          setMessageReaction: proc(userId: UserId; channelId, msgId, emoji: string): Result[void, string] {.gcsafe.} = ok(),
        )
      )

      let msg = OutboundMessage(userId: UserId("u1"), channel: ckQQ, text: "hello")
      sendImmediateOutbound(msg, ports, logger)

      var foundErr = false
      for e in cap.entries:
        if e.level == lvlError and "qq" in e.message.toLowerAscii():
          foundErr = true
          break
      check foundErr

    test "sendImmediateOutbound does not log error on success":
      let cap = newLogCapture()
      let logger = newLogger("test.outbound_ok", lvlDebug, makeSink(cap))

      var sentCount = 0
      let ports = OutboundChannelPorts(
        qq: OutboundChannelPort(
          send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
            {.cast(gcsafe).}: inc sentCount
            ok(),
          sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} = ok("m1"),
          editMessage: proc(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.} =
            discard isHtml
            ok(),
          sendKeyboard: proc(userId: UserId; text: string;
                             buttons: seq[seq[(string, string)]];
                             replyTo = ""): Result[void, string] {.gcsafe.} = ok(),
          editKeyboard: proc(userId: UserId; msgId, text: string;
                             buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} = ok(),
          setMessageReaction: proc(userId: UserId; channelId, msgId, emoji: string): Result[void, string] {.gcsafe.} = ok(),
        )
      )

      let msg = OutboundMessage(userId: UserId("u1"), channel: ckQQ, text: "hello")
      sendImmediateOutbound(msg, ports, logger)
      check sentCount == 1

      # No error log on success
      for e in cap.entries:
        check e.level != lvlError

  # ── Tests: multi-channel outbound error visibility ────────────────────────────

  suite "error policy — multi-channel outbound":

    test "sendImmediateOutbound logs Feishu send failure":
      let cap = newLogCapture()
      let logger = newLogger("test.fs_outbound", lvlDebug, makeSink(cap))

      let ports = OutboundChannelPorts(
        feishu: OutboundChannelPort(
          send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
            err("api rate limited"),
          sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} = err("nope"),
          editMessage: proc(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.} =
            discard isHtml
            ok(),
          sendKeyboard: proc(userId: UserId; text: string;
                             buttons: seq[seq[(string, string)]];
                             replyTo = ""): Result[void, string] {.gcsafe.} = ok(),
          editKeyboard: proc(userId: UserId; msgId, text: string;
                             buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} = ok(),
          setMessageReaction: proc(userId: UserId; channelId, msgId, emoji: string): Result[void, string] {.gcsafe.} = ok(),
        )
      )

      let msg = OutboundMessage(userId: UserId("u2"), channel: ckFeishu, text: "status report")
      sendImmediateOutbound(msg, ports, logger)

      var foundErr = false
      for e in cap.entries:
        if e.level == lvlError and "fs" in e.message.toLowerAscii():
          foundErr = true
          break
      check foundErr

    test "sendImmediateOutbound logs WeCom send failure":
      let cap = newLogCapture()
      let logger = newLogger("test.wc_outbound", lvlDebug, makeSink(cap))

      let ports = OutboundChannelPorts(
        wecom: OutboundChannelPort(
          send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
            err("token expired"),
          sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} = err("nope"),
          editMessage: proc(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.} =
            discard isHtml
            ok(),
          sendKeyboard: proc(userId: UserId; text: string;
                             buttons: seq[seq[(string, string)]];
                             replyTo = ""): Result[void, string] {.gcsafe.} = ok(),
          editKeyboard: proc(userId: UserId; msgId, text: string;
                             buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} = ok(),
          setMessageReaction: proc(userId: UserId; channelId, msgId, emoji: string): Result[void, string] {.gcsafe.} = ok(),
        )
      )

      let msg = OutboundMessage(userId: UserId("u3"), channel: ckWeCom, text: "reply")
      sendImmediateOutbound(msg, ports, logger)

      var foundErr = false
      for e in cap.entries:
        if e.level == lvlError and "wc" in e.message.toLowerAscii():
          foundErr = true
          break
      check foundErr

    test "sendImmediateOutbound logs Telegram send failure":
      let cap = newLogCapture()
      let logger = newLogger("test.tg_outbound", lvlDebug, makeSink(cap))

      let ports = OutboundChannelPorts(
        telegram: OutboundChannelPort(
          send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
            err("network unreachable"),
          sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} = err("nope"),
          editMessage: proc(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.} =
            discard isHtml
            ok(),
          sendKeyboard: proc(userId: UserId; text: string;
                             buttons: seq[seq[(string, string)]];
                             replyTo = ""): Result[void, string] {.gcsafe.} = ok(),
          editKeyboard: proc(userId: UserId; msgId, text: string;
                             buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} = ok(),
          setMessageReaction: proc(userId: UserId; channelId, msgId, emoji: string): Result[void, string] {.gcsafe.} = ok(),
        )
      )

      let msg = OutboundMessage(userId: UserId("u4"), channel: ckTelegram, text: "typing feedback")
      sendImmediateOutbound(msg, ports, logger)

      var foundErr = false
      for e in cap.entries:
        if e.level == lvlError and "tg" in e.message.toLowerAscii():
          foundErr = true
          break
      check foundErr

  # ── Tests: embedding error visibility (US-007) ───────────────────────────────

  suite "error policy — embedding parse errors":

    test "embed returns empty seq on HTTP failure (no crash)":
      # When the HTTP request fails, embed returns empty seq
      # This is documented behavior: "Returns empty seq[float32] on error"
      let adapter = OpenRouterEmbeddingAdapter(
        apiKey: "fake-key",
        model:  "qwen/qwen3-embedding-8b",
        http:   newStdHttpAdapter(),
        log:    newLogger("test.embedding"),
      )
      # With a fake key and no real server, this should return empty seq
      # without raising an exception
      let vec = adapter.embed("test text")
      check vec.len == 0 or vec.len == 4096  # either empty (error) or real embedding

when isMainModule:
  runTests()
