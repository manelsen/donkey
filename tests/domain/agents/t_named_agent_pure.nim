## Named agents, the pure part: the agent file, the @mention that calls one,
## and the system prompt of its turn.

import std/[options, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/agents/named_agent_pure

proc runTests*() =
  suite "named agents — the file":
    test "the four fields, comments and escapes":
      let a = parseAgentFile("""
# o revisor do time
name = "revisor"
description = "Revisa código com rigor; diz \"não\" quando precisa."
provider = "anthropic"
model = "claude-sonnet-5-5"
""")
      check a.isOk
      check a.get.name == "revisor"
      check a.get.description == "Revisa código com rigor; diz \"não\" quando precisa."
      check a.get.provider == "anthropic" and a.get.model == "claude-sonnet-5-5"

    test "provider and model are optional; name and description are not":
      check parseAgentFile("name = \"a\"\ndescription = \"b\"").get.provider == ""
      check parseAgentFile("description = \"b\"").isErr
      check parseAgentFile("name = \"a\"").isErr

    test "a bad name is refused":
      check parseAgentFile("name = \"../x\"\ndescription = \"b\"").isErr

    test "render and parse round-trip":
      let a = NamedAgent(name: "pesquisa", description: "Busca \"fontes\"\nprimárias",
                         provider: "gemini", model: "")
      check parseAgentFile(renderAgentFile(a)).get == a

    test "valid names":
      check validAgentName("revisor")
      check validAgentName("dev-ops2")
      check not validAgentName("")
      check not validAgentName("Revisor")
      check not validAgentName("a b")
      check not validAgentName("a/b")
      check not validAgentName('a'.repeat(33))

  suite "named agents — the mention":
    test "@name at the start calls that agent and is removed":
      let m = agentMention("@revisor olha esse diff")
      check m.isSome
      check m.get.name == "revisor" and m.get.text == "olha esse diff"

    test "case-insensitive, punctuation after the name":
      check agentMention("@Revisor, olha").get.name == "revisor"
      check agentMention("@revisor: olha").get.text == "olha"

    test "not at the start, an email or a bare @ is no call":
      check agentMention("fala com @revisor").isNone
      check agentMention("a@b.com").isNone
      check agentMention("@ oi").isNone
      check agentMention("@revisor").get.text == ""

  suite "named agents — the system prompt":
    test "the persona, the notes and the rest of the base":
      let a = NamedAgent(name: "revisor", description: "Revisa código com rigor.")
      let prompt = namedAgentSystem(a, notes = "- prefere PRs pequenos", toolsSuffix = "TOOLS")
      check "revisor" in prompt
      check "Revisa código com rigor." in prompt
      check "prefere PRs pequenos" in prompt
      check prompt.endsWith("TOOLS")

    test "no notes, no notes section":
      let prompt = namedAgentSystem(NamedAgent(name: "a", description: "d"), "", "")
      check "notes" notin prompt.toLowerAscii

proc runStrictTests*() =
  suite "named agent — a strict provider (audit of 26/11, finding 2)":
    test "a local provider is strict unless the file says otherwise":
      check parseAgentFile("name = \"a\"\ndescription = \"b\"\nprovider = \"ollama\"").get.providerIsStrict
      check not parseAgentFile("name = \"a\"\ndescription = \"b\"\nprovider = \"ollama\"\nstrict_provider = false").get.providerIsStrict

    test "a cloud provider is a preference unless the file makes it strict":
      check not parseAgentFile("name = \"a\"\ndescription = \"b\"\nprovider = \"openai\"").get.providerIsStrict
      check parseAgentFile("name = \"a\"\ndescription = \"b\"\nprovider = \"openai\"\nstrict_provider = true").get.providerIsStrict

    test "no provider is never strict; a bad value is an error":
      check not parseAgentFile("name = \"a\"\ndescription = \"b\"\nstrict_provider = true").get.providerIsStrict
      check parseAgentFile("name = \"a\"\ndescription = \"b\"\nstrict_provider = talvez").isErr

    test "the setting survives a round trip":
      let a = parseAgentFile("name = \"a\"\ndescription = \"b\"\nprovider = \"ollama\"\nstrict_provider = false").get
      check not parseAgentFile(renderAgentFile(a)).get.providerIsStrict

when isMainModule:
  runTests()
  runStrictTests()
