## Channel preference parsing — pure functions over raw text.
## Lives in app so it can use parsetoml without polluting core.
## Orchestrator imports THIS instead of common_runtime.

import parsetoml
import ../core/providers/smart_routing  ## for normalizeBudgetPolicy
import ../core/types                    ## ChannelPrefs, defaultChannelPrefs

proc parseChannelPrefs*(preferencesMd: string): ChannelPrefs =
  result = defaultChannelPrefs()
  if preferencesMd.len == 0:
    return
  try:
    {.cast(gcsafe).}:
      let t = parsetoml.parseString(preferencesMd)
      if t.hasKey("provider"):
        result.provider = t["provider"].getStr()
      if t.hasKey("model"):
        result.model = t["model"].getStr()
      if t.hasKey("thinking"):
        result.thinking = t["thinking"].getStr("off")
      if t.hasKey("budget"):
        result.budget = normalizeBudgetPolicy(t["budget"].getStr("balanced"))
      if t.hasKey("reasoning"):
        result.reasoning = t["reasoning"].getStr("on")
  except:
    discard