## Contract tests for the pure agent-chat gateway surface (US-001).
##
## Covers identity sanitisation, the request parser (400 shapes), the OpenAI
## response/chunk builders, reply-kind precedence and client redaction.
## No network, no clock, no provider.

import std/[json, strutils, unicode, unittest]
import results
import donkey/core/types
import donkey/domain/message
import donkey/domain/gateway/identity_pure
import donkey/domain/gateway/chat_request
import donkey/domain/gateway/chat_response
import donkey/domain/gateway/redact_pure

# ── identity ──────────────────────────────────────────────────────────────────

proc runTests*() =
  suite "apiUserId":

    test "accepts the declared alphabet and prefixes api:":
      for raw in ["a", "alice", "a.b_c-1", "user.42", repeat("a", 64)]:
        let res = apiUserId(raw)
        check res.isOk
        check $res.get() == "api:" & raw

    test "rejects empty, dot and dot-dot":
      check apiUserId("").isErr
      check apiUserId(".").isErr
      check apiUserId("..").isErr

    test "rejects slash, whitespace, uppercase and overlong names":
      for raw in ["a/b", "../etc", "Alice", "a b", "api:alice", repeat("a", 65)]:
        check apiUserId(raw).isErr

  suite "isApiChatReply":

    test "keys only on the userId prefix":
      check isApiChatReply(OutboundMessage(userId: UserId("api:alice")))
      check not isApiChatReply(OutboundMessage(userId: UserId("telegram:42")))

    test "replyTo and channelId do not make a channel message an API reply":
      check not isApiChatReply(OutboundMessage(
        userId: UserId("telegram:42"),
        replyTo: "api:alice",
      ))
      check isApiChatReply(OutboundMessage(
        userId: UserId("api:alice"),
        replyTo: "telegram:42",
      ))

    test "the prefix must be at the start, not merely contained":
      check not isApiChatReply(OutboundMessage(userId: UserId("telegram:api:x")))
      check not isApiChatReply(OutboundMessage(userId: UserId("x-api:alice")))
      check isApiChatReply(OutboundMessage(userId: UserId("api:alice")))

  suite "AuthVerdict":

    test "authorize is the ingress decision type":
      let policy: authorize =
        proc(userId: UserId): AuthVerdict {.gcsafe, raises: [].} =
          if $userId == "api:revoked": avRevoked else: avAllowed
      check policy(UserId("api:revoked")) == avRevoked
      check policy(UserId("api:alice")) == avAllowed
      check avNotAllowed != avAllowed

      let alias: AuthorizeFn = policy
      check alias(UserId("api:alice")) == avAllowed

  # ── request parsing ───────────────────────────────────────────────────────────

  suite "parseAgentChatRequest":

    test "a minimal request becomes an agent turn":
      let res = parseAgentChatRequest("""
      {"user": "alice", "messages": [{"role": "user", "content": "oi"}]}
    """)
      check res.isOk
      let req = res.get()
      check $req.userId == "api:alice"
      check req.text == "oi"
      check not req.stream

    test "missing user is a 400 invalid_request_error":
      let res = parseAgentChatRequest("""
      {"messages": [{"role": "user", "content": "oi"}]}
    """)
      check res.isErr
      check res.error.status == 400
      check res.error.errorType == "invalid_request_error"
      check res.error.code == "missing_required_parameter"
      check res.error.param == "user"
      let body = parseJson(res.error.body)
      check body["error"]["type"].getStr() == "invalid_request_error"
      check body["error"]["code"].getStr() == "missing_required_parameter"

    test "a path-like user is refused by the identity rules":
      for raw in ["../", "..", ".", "Alice", "a/b"]:
        let res = parseAgentChatRequest("""
        {"user": "$#", "messages": [{"role": "user", "content": "oi"}]}
      """.replace("$#", raw))
        check res.isErr
        check res.error.status == 400
        check res.error.errorType == "invalid_request_error"
        check res.error.param == "user"

    test "stream is accepted and carried":
      let res = parseAgentChatRequest("""
      {"user": "alice", "stream": true,
       "messages": [{"role": "user", "content": "oi"}]}
    """)
      check res.isOk
      check res.get().stream

    test "client tools are refused as unsupported_parameter":
      let res = parseAgentChatRequest("""
      {"user": "alice", "messages": [{"role": "user", "content": "oi"}],
       "tools": [{"type": "function"}]}
    """)
      check res.isErr
      check res.error.status == 400
      check res.error.code == "unsupported_parameter"
      check res.error.param == "tools"

    test "tool_choice, response_format and n>1 are refused":
      for (extra, param) in [
        (""""tool_choice": "auto",""", "tool_choice"),
        (""""response_format": {"type": "json_object"},""", "response_format"),
        (""""n": 2,""", "n"),
      ]:
        let body = """
        {"user": "alice", $#"messages": [{"role": "user", "content": "oi"}]}
      """.replace("$#", extra)
        let res = parseAgentChatRequest(body)
        check res.isErr
        check res.error.status == 400
        check res.error.code == "unsupported_parameter"
        check res.error.param == param
        check parseJson(res.error.body)["error"]["param"].getStr() == param

    test "n as a float above 1 or as a string is refused":
      for n in ["2.0", "1.5", "\"2\"", "\"1\""]:
        let body = """
        {"user": "alice", "n": $#,
         "messages": [{"role": "user", "content": "oi"}]}
      """.replace("$#", n)
        let res = parseAgentChatRequest(body)
        check res.isErr
        check res.error.code == "unsupported_parameter"
        check res.error.param == "n"

    test "n as a non-numeric JSON value is refused":
      for n in ["true", "false", "[1]", "{\"n\": 1}"]:
        let body = """
        {"user": "alice", "n": $#,
         "messages": [{"role": "user", "content": "oi"}]}
      """.replace("$#", n)
        let res = parseAgentChatRequest(body)
        check res.isErr
        check res.error.code == "unsupported_parameter"
        check res.error.param == "n"

    test "n as null is treated as absent":
      let res = parseAgentChatRequest("""
      {"user": "alice", "n": null,
       "messages": [{"role": "user", "content": "oi"}]}
    """)
      check res.isOk

    test "n as zero or negative is refused":
      for n in ["0", "-1", "0.0", "-1.0"]:
        let body = """
        {"user": "alice", "n": $#,
         "messages": [{"role": "user", "content": "oi"}]}
      """.replace("$#", n)
        let res = parseAgentChatRequest(body)
        check res.isErr
        check res.error.code == "unsupported_parameter"
        check res.error.param == "n"

    test "n as a float of 1 is harmless":
      let res = parseAgentChatRequest("""
      {"user": "alice", "n": 1.0,
       "messages": [{"role": "user", "content": "oi"}]}
    """)
      check res.isOk

    test "empty or whitespace user content is rejected":
      for body in [
        """{"user":"alice","messages":[{"role":"user","content":""}]}""",
        """{"user":"alice","messages":[{"role":"user","content":"   "}]}""",
        """{"user":"alice","messages":[{"role":"user","content":"\t\n  "}]}""",
      ]:
        let res = parseAgentChatRequest(body)
        check res.isErr
        check res.error.status == 400
        check res.error.errorType == "invalid_request_error"
        check res.error.param == "messages"

    test "n=1 is harmless":
      let res = parseAgentChatRequest("""
      {"user": "alice", "n": 1,
       "messages": [{"role": "user", "content": "oi"}]}
    """)
      check res.isOk

    test "system and developer messages are refused":
      for role in ["system", "developer"]:
        let body = """
        {"user": "alice", "messages": [
          {"role": "$#", "content": "you are"},
          {"role": "user", "content": "oi"}
        ]}
      """.replace("$#", role)
        let res = parseAgentChatRequest(body)
        check res.isErr
        check res.error.status == 400
        check res.error.code == "unsupported_parameter"
        check res.error.param == "messages"

    test "the last message must be from the user":
      let res = parseAgentChatRequest("""
      {"user": "alice", "messages": [
        {"role": "user", "content": "oi"},
        {"role": "assistant", "content": "olá"}
      ]}
    """)
      check res.isErr
      check res.error.status == 400
      check res.error.errorType == "invalid_request_error"

    test "prior history is ignored: the session owns it":
      let res = parseAgentChatRequest("""
      {"user": "alice", "messages": [
        {"role": "user", "content": "antigo"},
        {"role": "assistant", "content": "resposta antiga"},
        {"role": "user", "content": "agora"}
      ]}
    """)
      check res.isOk
      check res.get().text == "agora"

    test "temperature, top_p and max_tokens are ignored":
      let res = parseAgentChatRequest("""
      {"user": "alice", "temperature": 1.9, "top_p": "loud",
       "max_tokens": -5,
       "messages": [{"role": "user", "content": "oi"}]}
    """)
      check res.isOk
      check res.get().text == "oi"

    test "content parts contribute their text":
      let res = parseAgentChatRequest("""
      {"user": "alice", "messages": [{"role": "user", "content": [
        {"type": "text", "text": "olá"},
        {"type": "text", "text": "mundo"}
      ]}]}
    """)
      check res.isOk
      check res.get().text == "olá\nmundo"

    test "invalid JSON is a 400":
      let res = parseAgentChatRequest("not json")
      check res.isErr
      check res.error.status == 400
      check res.error.errorType == "invalid_request_error"

  # ── response builders ─────────────────────────────────────────────────────────

  suite "agent response builders":

    test "chat.completion carries the final text and usage":
      let node = parseJson(buildAgentChatResponse(
        "olá", "donkey/default", "chatcmpl-1", 100, 3, 5))
      check node["id"].getStr() == "chatcmpl-1"
      check node["object"].getStr() == "chat.completion"
      check node["created"].getInt() == 100
      check node["choices"][0]["message"]["role"].getStr() == "assistant"
      check node["choices"][0]["message"]["content"].getStr() == "olá"
      check node["choices"][0]["finish_reason"].getStr() == "stop"
      check node["usage"]["prompt_tokens"].getInt() == 3
      check node["usage"]["completion_tokens"].getInt() == 5
      check node["usage"]["total_tokens"].getInt() == 8

    test "the first chunk carries role and no finish_reason":
      let node = parseJson(buildAgentChunk(
        "chatcmpl-1", "donkey/default", 100, role = "assistant"))
      check node["object"].getStr() == "chat.completion.chunk"
      check node["choices"][0]["delta"]["role"].getStr() == "assistant"
      check not node["choices"][0].hasKey("finish_reason")
      check not node["choices"][0]["delta"].hasKey("content")

    test "middle chunks carry content without role or finish_reason":
      let node = parseJson(buildAgentChunk(
        "chatcmpl-1", "donkey/default", 100, content = "ol"))
      check node["choices"][0]["delta"]["content"].getStr() == "ol"
      check not node["choices"][0]["delta"].hasKey("role")
      check not node["choices"][0].hasKey("finish_reason")

    test "the last chunk carries finish_reason and usage":
      let node = parseJson(buildAgentChunk(
        "chatcmpl-1", "donkey/default", 100, finishReason = "stop",
        inputTokens = 3, outputTokens = 5))
      check node["choices"][0]["finish_reason"].getStr() == "stop"
      check not node["choices"][0]["delta"].hasKey("role")
      check node["usage"]["prompt_tokens"].getInt() == 3
      check node["usage"]["completion_tokens"].getInt() == 5
      check node["usage"]["total_tokens"].getInt() == 8

    test "tool call deltas are informative, not content":
      let node = parseJson(buildAgentChunk(
        "chatcmpl-1", "donkey/default", 100,
        toolCall = ToolCallNotice(phase: "start", name: "fs_read", id: "call-1")))
      let delta = node["choices"][0]["delta"]
      check delta["tool_calls"][0]["id"].getStr() == "call-1"
      check delta["tool_calls"][0]["function"]["name"].getStr() == "fs_read"
      check not delta.hasKey("content")

    test "errors are OpenAI-shaped and redacted":
      let node = parseJson(buildAgentError(
        "provider failed: Bearer abc123 sk-fake key=secret token=tok-999",
        "server_error", "provider_error"))
      check node["error"]["type"].getStr() == "server_error"
      check node["error"]["code"].getStr() == "provider_error"
      let message = node["error"]["message"].getStr()
      check not message.contains("abc123")
      check not message.contains("sk-fake")
      check not message.contains("secret")
      check not message.contains("tok-999")

    test "sseDone is the OpenAI terminator":
      check sseDone() == "data: [DONE]\n\n"

    test "sseData frames exactly one event per chunk":
      check sseData("{\"object\":\"chat.completion.chunk\"}") ==
            "data: {\"object\":\"chat.completion.chunk\"}\n\n"
      check sseData("{\"error\":{\"message\":\"x\"}}") ==
            "data: {\"error\":{\"message\":\"x\"}}\n\n"

  suite "deltaText precedence":

    test "final answers and turn errors are content":
      check deltaText("olá", rkFinalAnswer) == "olá"
      check deltaText("olá", rkTurnError) == "olá"
      check deltaText(OutboundMessage(
        userId: UserId("api:a"), text: "olá", replyKind: rkFinalAnswer)) == "olá"

    test "turn error deltas are redacted before leaving the process":
      let msg = OutboundMessage(
        userId: UserId("api:a"),
        text: "provider failed: Bearer abc123 sk-fake key=secret token=tok456",
        replyKind: rkTurnError,
      )
      let text = deltaText(msg)
      check text.len > 0
      check not text.contains("abc123")
      check not text.contains("sk-fake")
      check not text.contains("secret")
      check not text.contains("tok456")
      # Final answers are model content, not diagnostics: they are not rewritten.
      check deltaText("olá Bearer abc123", rkFinalAnswer) == "olá Bearer abc123"

    test "partial final answers still stream their text":
      check deltaText(OutboundMessage(
        userId: UserId("api:a"), text: "ol", replyKind: rkFinalAnswer,
        isPartial: true)) == "ol"

    test "tool notices, debug and channel chatter are never content":
      check deltaText("🔧 fs_read", rkToolNotice) == ""
      check deltaText("debug", rkDebug) == ""
      check deltaText("canal", rkChannel) == ""
      check deltaText(OutboundMessage(
        userId: UserId("api:a"), text: "🔧 fs_read",
        replyKind: rkToolNotice, isPartial: false,
        toolCall: ToolCallNotice(phase: "start", name: "fs_read"))) == ""

    test "replyKind wins over a stale toolCall field":
      let msg = OutboundMessage(
        userId: UserId("api:a"), text: "resposta",
        replyKind: rkFinalAnswer,
        toolCall: ToolCallNotice(phase: "done", name: "fs_read"))
      check deltaText(msg) == "resposta"

  suite "redactForClient":

    test "removes bearer tokens, sk- keys, key= and token= values":
      let redacted = redactForClient(
        "Authorization: Bearer abc123; sk-fake key=secret token=tok123")
      check not redacted.contains("abc123")
      check not redacted.contains("sk-fake")
      check not redacted.contains("secret")
      check not redacted.contains("tok123")
      check redacted.contains("Authorization:")

    test "accepts tabs and repeated whitespace after Bearer":
      let redacted = redactForClient(
        "a Bearer\tabc123 b Bearer    def456 c Bearer\nghi789")
      check not redacted.contains("abc123")
      check not redacted.contains("def456")
      check not redacted.contains("ghi789")
      check redacted.contains(RedactedPlaceholder)

    test "accepts spaces around = for key and token":
      let redacted = redactForClient("?key = secret&token = tok123&safe=ok")
      check not redacted.contains("secret")
      check not redacted.contains("tok123")
      check redacted.contains("safe=ok")

    test "accepts CR, vertical tab and form feed after Bearer":
      let redacted = redactForClient(
        "a Bearer\rabc123 b Bearer\vdef456 c Bearer\fghi789")
      check not redacted.contains("abc123")
      check not redacted.contains("def456")
      check not redacted.contains("ghi789")

    test "quoted secret values do not survive the quote":
      let redacted = redactForClient(
        "key=\"secret\" Bearer \"abc123\" token='tok123' safe=\"visible\"")
      check not redacted.contains("secret")
      check not redacted.contains("abc123")
      check not redacted.contains("tok123")
      check redacted.contains("safe=\"visible\"")

    test "redacts Basic auth and common token prefixes":
      let redacted = redactForClient(
        "Authorization: Basic dXNlcjpwYXNz xoxb-1234-5678 ghp_abcdef " &
        "AKIAIOSFODNN7EXAMPLE AIzaSyA123456789")
      check not redacted.contains("dXNlcjpwYXNz")
      check not redacted.contains("xoxb-1234")
      check not redacted.contains("ghp_abcdef")
      check not redacted.contains("AKIAIOSFODNN7EXAMPLE")
      check not redacted.contains("AIzaSyA123456789")
      check redacted.contains(RedactedPlaceholder)

    test "redacts JSON-style secret keys with a colon":
      let redacted = redactForClient(
        "{\"api_key\": \"secret-value\", \"token\": \"tok-9\"}")
      check not redacted.contains("secret-value")
      check not redacted.contains("tok-9")

    test "redacts JSON keys with a space before the colon":
      let redacted = redactForClient("{\"api_key\" : \"secret-value\"}")
      check not redacted.contains("secret-value")

    test "prose that merely contains key: or token: is left alone":
      let redacted = redactForClient("monkey: business, token: counting")
      check redacted == "monkey: business, token: counting"

    test "caps the payload at 300 characters":
      let redacted = redactForClient(repeat("a", 1000) & " sk-fake")
      check redacted.len <= 300
      check not redacted.contains("sk-fake")

    test "the 300-byte cap never splits a multi-byte character":
      let emoji = repeat("a", 298) & "😀" & repeat("b", 40)
      let redactedEmoji = redactForClient(emoji)
      check redactedEmoji.len <= 300
      check redactedEmoji.len == 298
      check validateUtf8(redactedEmoji) == -1

      let cjk = repeat("a", 299) & "漢" & repeat("b", 40)
      let redactedCjk = redactForClient(cjk)
      check redactedCjk.len <= 300
      check redactedCjk.len == 299
      check validateUtf8(redactedCjk) == -1

when isMainModule:
  runTests()
