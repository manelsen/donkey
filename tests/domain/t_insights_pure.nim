## Insights (E7.8): the per-turn traces summed into a report: turns, tokens,
## the tools used most and how often they failed, providers, channels and
## outcomes. After hermes-agent (MIT), agent/insights.py, from Donkey's
## traces (which never hold what was said).

import std/[strutils, unittest]
import donkey/domain/insights_pure

proc line(user = "u1"; provider = "openrouter"; channel = "telegram";
          tools = """[{"name":"web_search","outcome":"output"}]""";
          inTok = 100; outTok = 20; outcome = "ok"): string =
  """{"ts":1,"duration_ms":1000,"user":"""" & user & """","channel":"""" & channel &
    """","kind":"user","session":"s","provider":"""" & provider &
    """","streamed":true,"tools":""" & tools & ""","tokens":{"input":""" & $inTok &
    ""","output":""" & $outTok & """},"outcome":"""" & outcome & """"}"""

proc runTests*() =
  suite "insights":

    test "turns and tokens are summed":
      let r = aggregateInsights(@[line(), line(inTok = 50, outTok = 5)])
      check r.turns == 2 and r.inputTokens == 150 and r.outputTokens == 25

    test "tools are counted with their failures, the most used first":
      let r = aggregateInsights(@[
        line(tools = """[{"name":"bash","outcome":"operational_error"},{"name":"web_search","outcome":"output"}]"""),
        line(tools = """[{"name":"bash","outcome":"output"}]""")])
      check r.tools[0].name == "bash" and r.tools[0].calls == 2 and r.tools[0].failures == 1
      check r.tools[1].name == "web_search" and r.tools[1].calls == 1

    test "providers, channels and outcomes are counted":
      let r = aggregateInsights(@[line(), line(provider = "groq", channel = "cli", outcome = "provider_error")])
      check ("openrouter", 1) in r.providers and ("groq", 1) in r.providers
      check ("cli", 1) in r.channels
      check ("provider_error", 1) in r.outcomes

    test "a broken line is skipped, not fatal":
      check aggregateInsights(@["not json", line()]).turns == 1

    test "the report reads as text":
      let text = formatInsights(aggregateInsights(@[line(), line()]), "last 30 days")
      check "2 turns" in text and "web_search" in text and "openrouter" in text
      check "last 30 days" in text
      check formatInsights(aggregateInsights(@[]), "x").contains("No turns")

when isMainModule:
  runTests()
