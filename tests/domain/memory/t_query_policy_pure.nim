import std/unittest
import donkey/domain/memory/query_policy_pure

proc runTests*() =
  suite "query policy":

    test "default policy weighs meaning and literal terms equally":
      let p = defaultPolicy()
      check p.intent == qiSemantic
      check p.semanticWeight == 0.5
      check p.lexicalWeight == 0.5
      check p.temporalWeight == 0.0
      check p.neighborWeight == 0.0

    test "a temporal query adds recency and adjacency":
      let p = classifyQuery("when did I start the project?")
      check p.intent == qiTemporal
      check p.temporalWeight > 0.0
      check p.neighborWeight > 0.0
      check p.semanticWeight + p.lexicalWeight + p.temporalWeight +
            p.neighborWeight == 1.0

    test "the temporal policy has a name a router can ask for":
      check classifyQuery("when did I start the project?") == temporalPolicy()
      check classifyQuery("what is my wifi password?") == defaultPolicy()
      check temporalPolicy().intent == qiTemporal

    test "entity and causal wording do not change the policy":
      check classifyQuery("who is Alice?") == defaultPolicy()
      check classifyQuery("why did the deployment roll back?") == defaultPolicy()
      check classifyQuery("programming languages") == defaultPolicy()

    test "questions about time are recognised in Portuguese":
      for query in ["quando comecei o projeto?", "o que falamos ontem?",
                    "qual foi o Último deploy?", "o que decidimos antes disso?",
                    "o que mudou recentemente?", "e depois da reunião?",
                    "o que eu disse semana passada?", "isso foi dois dias atrás",
                    "qual foi a primeira versão?", "o que combinamos hoje?",
                    "mostre em ordem cronológica", "e na conversa anterior?"]:
        check asksAboutTime(query)

    test "questions about time are recognised in English":
      for query in ["when did I start the project?", "what did we say yesterday?",
                    "the last deploy", "what changed recently?", "two days ago",
                    "show it chronologically"]:
        check asksAboutTime(query)

    test "a time word inside another word does not count":
      for query in ["o arquivo contem o codinome", "lista de estudantes",
                    "elastic search config", "authentication error",
                    "linguagens de programação", ""]:
        check not asksAboutTime(query)

when isMainModule:
  runTests()
