## insights_pure — the per-turn traces summed into a report (E7.8).
##
## Turns, tokens, the tools used most and how often they failed, providers,
## channels and outcomes, from the trace lines (domain/turn_trace_pure),
## which never hold what was said. After hermes-agent (MIT),
## agent/insights.py.

import std/[algorithm, json, strutils, tables]

type
  ToolUse* = object
    name*:     string
    calls*:    int
    failures*: int

  Insights* = object
    turns*, inputTokens*, outputTokens*: int
    cacheReadTokens*, cacheWriteTokens*: int
    cacheByProvider*: seq[(string, int, int)]   ## provider, input, read from cache
    tools*:     seq[ToolUse]
    providers*: seq[(string, int)]
    channels*:  seq[(string, int)]
    outcomes*:  seq[(string, int)]

func ranked(t: CountTable[string]): seq[(string, int)] =
  for k, v in t: result.add (k, v)
  result.sort(proc(a, b: (string, int)): int =
    if a[1] != b[1]: cmp(b[1], a[1]) else: cmp(a[0], b[0]))

proc aggregateInsights*(lines: seq[string]): Insights =
  var providers, channels, outcomes: CountTable[string]
  var calls, failures: CountTable[string]
  var provIn, provRead: CountTable[string]
  for raw in lines:
    let j =
      try: parseJson(raw)
      except CatchableError: continue
    if j.kind != JObject: continue
    inc result.turns
    result.inputTokens += j{"tokens"}{"input"}.getInt
    result.outputTokens += j{"tokens"}{"output"}.getInt
    let read = j{"tokens"}{"cache_read"}.getInt
    result.cacheReadTokens += read
    result.cacheWriteTokens += j{"tokens"}{"cache_write"}.getInt
    let provider = j{"provider"}.getStr
    if provider.len > 0:
      providers.inc provider
      provIn.inc(provider, j{"tokens"}{"input"}.getInt)
      provRead.inc(provider, read)
    let channel = j{"channel"}.getStr
    if channel.len > 0: channels.inc channel
    let outcome = j{"outcome"}.getStr
    if outcome.len > 0: outcomes.inc outcome
    for t in j{"tools"}.getElems:
      let name = t{"name"}.getStr
      if name.len == 0: continue
      calls.inc name
      if t{"outcome"}.getStr notin ["output", ""]: failures.inc name
  for (name, n) in ranked(calls):
    result.tools.add ToolUse(name: name, calls: n, failures: failures.getOrDefault(name))
  result.providers = ranked(providers)
  result.channels = ranked(channels)
  result.outcomes = ranked(outcomes)
  for (name, input) in ranked(provIn):
    result.cacheByProvider.add (name, input, provRead.getOrDefault(name))

func counts(items: seq[(string, int)]): string =
  var parts: seq[string]
  for (k, v) in items: parts.add k & " " & $v
  parts.join(", ")

func formatInsights*(r: Insights; period: string; toolLimit = 10): string =
  if r.turns == 0:
    return "No turns in " & period & " (traces are kept with DONKEY_TRACES=on)."
  var lines = @["Insights, " & period & ": " & $r.turns & " turns, " &
                $r.inputTokens & " tokens in, " & $r.outputTokens & " out."]
  if r.cacheReadTokens + r.cacheWriteTokens > 0 and r.inputTokens > 0:
    lines.add "Prompt cache: " & $r.cacheReadTokens & " of " & $r.inputTokens &
      " input tokens (" & $(r.cacheReadTokens * 100 div r.inputTokens) & "%), " &
      $r.cacheWriteTokens & " written."
    var parts: seq[string]
    for (name, input, read) in r.cacheByProvider:
      if input > 0: parts.add name & " " & $(read * 100 div input) & "%"
    if parts.len > 0: lines.add "  by provider: " & parts.join(", ")
  if r.tools.len > 0:
    lines.add "Tools:"
    for i, t in r.tools:
      if i >= toolLimit: break
      lines.add "  " & t.name & ": " & $t.calls &
        (if t.failures > 0: " (" & $t.failures & " failed)" else: "")
  if r.providers.len > 0: lines.add "Providers: " & counts(r.providers)
  if r.channels.len > 0: lines.add "Channels: " & counts(r.channels)
  if r.outcomes.len > 0: lines.add "Outcomes: " & counts(r.outcomes)
  lines.join("\n")
