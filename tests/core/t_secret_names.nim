import std/[strutils, unittest]
import donkey/core/security/secret_names

suite "secret names":

  test "accepts env-safe names":
    check isValidSecretName("OPENROUTER_API_KEY")
    check isValidSecretName("_private")
    check isValidSecretName("A1_b2")

  test "rejects invalid names":
    check not isValidSecretName("")
    check not isValidSecretName("1LEADING_DIGIT")
    check not isValidSecretName("HAS-DASH")
    check not isValidSecretName("HAS SPACE")
    check not isValidSecretName("PUNCT!")
    check not isValidSecretName("A" & repeat("B", MaxSecretNameLength))
