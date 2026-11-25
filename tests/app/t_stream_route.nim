## The route a turn streams through is the one routing would try first:
## the same selection, the same provider override.

import std/[options, unittest]
import donkey/app/credential_runtime
import donkey/app/session_bootstrap
import donkey/domain/message
import donkey/ports/provider

proc clearCreds() =
  resetCredentialPools()
  for name in ["OPENAI_API_KEY", "OPENAI_API_KEYS", "ANTHROPIC_API_KEY",
               "ANTHROPIC_API_KEYS", "OPENROUTER_API_KEY", "OPENROUTER_API_KEYS"]:
    setCredentialForTest(name, "")

func ask(text: string; providerOverride = ""; modelOverride = ""): CompletionRequest =
  CompletionRequest(messages: @[ChatMessage(role: roleUser, text: text)],
                    providerOverride: providerOverride,
                    modelOverride: modelOverride)

proc runTests*() =
  suite "stream route":

    test "the preferred provider is the stream's route, with its key":
      clearCreds()
      defer: clearCreds()
      setCredentialForTest("OPENAI_API_KEY", "sk-openai")
      let route = buildStreamRouteFn("provider = \"openai\"")(ask("oi"))
      check route.isSome
      check route.get.providerName == "openai"
      check route.get.apiKey == "sk-openai"

    test "a named agent's provider comes first, as in routing":
      clearCreds()
      defer: clearCreds()
      setCredentialForTest("OPENAI_API_KEY", "sk-openai")
      setCredentialForTest("ANTHROPIC_API_KEY", "sk-ant")
      let route = buildStreamRouteFn("provider = \"openai\"")(
        ask("oi", providerOverride = "anthropic", modelOverride = "claude-x"))
      check route.isSome
      check route.get.providerName == "anthropic"
      check route.get.modelName == "claude-x"

    test "no configured provider, no route":
      clearCreds()
      defer: clearCreds()
      check buildStreamRouteFn("")(ask("oi")).isNone

when isMainModule:
  runTests()
