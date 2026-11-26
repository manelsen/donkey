## Insights (E7.8): the per-turn traces summed into a report: turns, tokens,
## the tools used most and how often they failed, providers, channels and
## outcomes. After hermes-agent (MIT), agent/insights.py, from Donkey's
## traces (which never hold what was said).

import std/[strutils, unittest]
import donkey/domain/insights_pure

proc line(user = "u1"; provider = "openrouter"; channel = "telegram";
          tools = """[{"name":"web_search","outcome":"output"}]""";
          inTok = 100; outTok = 20; outcome = "ok"; cacheRead = -1): string =
  """{"ts":1,"duration_ms":1000,"user":"""" & user & """","channel":"""" & channel &
    """","kind":"user","session":"s","provider":"""" & provider &
    """","streamed":true,"tools":""" & tools & ""","tokens":{"input":""" & $inTok &
    ""","output":""" & $outTok &
    (if cacheRead >= 0: ""","cache_read":""" & $cacheRead else: "") &
    """},"outcome":"""" & outcome & """"}"""

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

    test "the prompt cache: how much of the input it served, per provider (E8.3)":
      let r = aggregateInsights(@[line(inTok = 1000, cacheRead = 800),
                                  line(provider = "groq", inTok = 1000, cacheRead = 0),
                                  line(inTok = 1000)])   ## an old line, before E8.3
      check r.cacheReadTokens == 800
      let text = formatInsights(r, "x")
      check "Prompt cache: 800 of 3000 input tokens (26%)" in text
      check "openrouter 40%" in text and "groq 0%" in text

    test "a provider whose large prompts never hit the cache is flagged (E8.4)":
      var lines: seq[string]
      for i in 0 ..< 5: lines.add line(provider = "anthropic", inTok = 5000, cacheRead = 0)
      for i in 0 ..< 5: lines.add line(provider = "openrouter", inTok = 5000, cacheRead = 3000)
      for i in 0 ..< 4: lines.add line(provider = "groq", inTok = 5000, cacheRead = 0)  ## too few
      for i in 0 ..< 9: lines.add line(provider = "deepseek", inTok = 900, cacheRead = 0) ## too small
      for i in 0 ..< 9: lines.add line(provider = "gemini", inTok = 5000)               ## before E8.3
      let r = aggregateInsights(lines)
      check r.cacheSilent == @[("anthropic", 5)]
      check "anthropic: 5 large prompts" in formatInsights(r, "x")

    test "no cached tokens: no cache line":
      check "Prompt cache" notin formatInsights(aggregateInsights(@[line()]), "x")

    test "a broken line is skipped, not fatal":
      check aggregateInsights(@["not json", line()]).turns == 1

    test "the report reads as text":
      let text = formatInsights(aggregateInsights(@[line(), line()]), "last 30 days")
      check "2 turns" in text and "web_search" in text and "openrouter" in text
      check "last 30 days" in text
      check formatInsights(aggregateInsights(@[]), "x").contains("No turns")

when isMainModule:
  runTests()
