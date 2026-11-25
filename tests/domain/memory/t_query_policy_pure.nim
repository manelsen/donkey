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

    test "a question about a recent period adds recency and adjacency":
      let p = classifyQuery("what did we talk about yesterday?")
      check p.intent == qiTemporal
      check p.temporalWeight > 0.0
      check p.neighborWeight > 0.0
      check p.semanticWeight + p.lexicalWeight + p.temporalWeight +
            p.neighborWeight == 1.0

    test "the temporal policy has a name a router can ask for":
      check classifyQuery("what did we say yesterday?") == temporalPolicy()
      check classifyQuery("what is my wifi password?") == defaultPolicy()
      check temporalPolicy().intent == qiTemporal

    test "a question about order or a date ranks by meaning and words":
      ## "Which came first?" needs both events found by what they are, not
      ## the newest memories: with recency at 0.40 the answer was buried
      ## (bench/search/RESULTS.md, LongMemEval and the router comparison).
      for query in ["which happened first, the purchase or the repair?",
                    "when did I start the project?", "what did we decide before that?",
                    "and after the meeting?", "what came earlier?", "and then?",
                    "quando comecei o projeto?", "o que decidimos antes disso?",
                    "e depois da reunião?", "qual foi a primeira versão?",
                    "mostre em ordem cronológica", "e na conversa anterior?",
                    "what was the discount on my first purchase?"]:
        check classifyQuery(query) == defaultPolicy()

    test "entity and causal wording do not change the policy":
      check classifyQuery("who is Alice?") == defaultPolicy()
      check classifyQuery("why did the deployment roll back?") == defaultPolicy()
      check classifyQuery("programming languages") == defaultPolicy()

    test "questions about a recent period are recognised in Portuguese":
      for query in ["o que falamos ontem?", "e anteontem?", "qual foi o Último deploy?",
                    "o que mudou recentemente?", "o que eu disse semana passada?",
                    "isso foi dois dias atrás", "o que combinamos hoje?"]:
        check asksAboutRecentPeriod(query)

    test "questions about a recent period are recognised in English":
      for query in ["what did we say yesterday?", "the last deploy",
                    "what changed recently?", "two days ago", "what did I say today?"]:
        check asksAboutRecentPeriod(query)

    test "a time word inside another word does not count":
      for query in ["o arquivo contem o codinome", "lista de estudantes",
                    "elastic search config", "authentication error",
                    "linguagens de programação", ""]:
        check not asksAboutRecentPeriod(query)

proc runRelativeDateTests*() =
  suite "a relative date makes a question temporal":
    test "há 3 dias, two weeks ago, semana passada":
      check classifyQuery("o que falamos há 3 dias?").intent == qiTemporal
      check classifyQuery("what did I say two weeks ago").intent == qiTemporal
      check classifyQuery("o que fizemos semana passada").intent == qiTemporal
      check classifyQuery("qual é a senha do wifi?").intent == qiSemantic

when isMainModule:
  runTests()
  runRelativeDateTests()
