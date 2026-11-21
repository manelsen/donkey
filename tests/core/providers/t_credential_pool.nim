## Credential pool tests: rotation, cooldown and retry classification.

import std/[options, unittest]
import donkey/core/providers/credential_pool

proc runTests*() =
  suite "credential pool selection":

    test "an empty pool picks nothing":
      var pool = initCredentialPool(@[])
      check pool.pick(0).isNone

    test "round-robins through healthy keys":
      var pool = initCredentialPool(@["a", "b", "c"])
      check pool.pick(0) == some("a")
      check pool.pick(0) == some("b")
      check pool.pick(0) == some("c")
      check pool.pick(0) == some("a")

    test "skips a key that is cooling down":
      var pool = initCredentialPool(@["a", "b"])
      check pool.pick(0) == some("a")
      pool.noteFailure("a", nowMs = 100, cooldownMs = 500)
      check pool.pick(100) == some("b")
      check pool.pick(100) == some("b")

    test "a cooled key returns after the deadline":
      var pool = initCredentialPool(@["a", "b"])
      pool.noteFailure("a", nowMs = 100, cooldownMs = 500)
      check pool.pick(700) == some("a")

    test "when every key is cooling, the earliest deadline wins":
      var pool = initCredentialPool(@["a", "b"])
      pool.noteFailure("a", nowMs = 100, cooldownMs = 900)
      pool.noteFailure("b", nowMs = 100, cooldownMs = 400)
      check pool.pick(200) == some("b")

    test "success clears a cooldown":
      var pool = initCredentialPool(@["a"])
      pool.noteFailure("a", nowMs = 100, cooldownMs = 5000)
      pool.noteSuccess("a")
      check pool.pick(101) == some("a")

    test "an unknown key is ignored":
      var pool = initCredentialPool(@["a"])
      pool.noteFailure("zzz", nowMs = 100, cooldownMs = 5000)
      check pool.pick(101) == some("a")

  suite "credential pool next healthy":

    test "returns a different healthy key":
      let pool = initCredentialPool(@["a", "b"])
      check pool.nextHealthy("a", 0) == some("b")

    test "skips a cooling key":
      var pool = initCredentialPool(@["a", "b", "c"])
      pool.noteFailure("b", nowMs = 0, cooldownMs = 500)
      check pool.nextHealthy("a", 0) == some("c")

    test "no alternative means empty":
      var pool = initCredentialPool(@["a", "b"])
      pool.noteFailure("b", nowMs = 0, cooldownMs = 500)
      check pool.nextHealthy("a", 0).isNone
      check initCredentialPool(@["a"]).nextHealthy("a", 0).isNone

  suite "credential error classification":

    test "auth, rate and quota failures are retryable with another key":
      check isRetryableCredentialError("401 Unauthorized")
      check isRetryableCredentialError("invalid api key")
      check isRetryableCredentialError("429 Too Many Requests")
      check isRetryableCredentialError("rate limit exceeded")
      check isRetryableCredentialError("insufficient_quota")
      check isRetryableCredentialError("quota exceeded for this key")

    test "transport and payload failures are not key problems":
      check not isRetryableCredentialError("connection reset by peer")
      check not isRetryableCredentialError("500 internal server error")
      check not isRetryableCredentialError("context length exceeded")

when isMainModule:
  runTests()
