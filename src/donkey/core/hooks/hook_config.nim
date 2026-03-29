## hook_config — Hook configuration loading and management.

import std/[options, strtabs, json, tables]
import ../../ports/hook
import ../../core/types

type
  HookConfig* = object
    name*:    string
    enabled*: bool
    phase*:   HookPhase
    params*:  StringTableRef

  HookConfigLoader* = object
    configs*: seq[HookConfig]

func newHookConfigLoader*(): HookConfigLoader =
  HookConfigLoader(configs: @[])

func addHookConfig*(loader: var HookConfigLoader; cfg: HookConfig) =
  loader.configs.add(cfg)

func getHookConfig*(loader: HookConfigLoader; name: string): Option[HookConfig] =
  for cfg in loader.configs:
    if cfg.name == name:
      return some(cfg)
  none(HookConfig)

func getHooksForPhase*(loader: HookConfigLoader; phase: HookPhase; onlyEnabled: bool = true): seq[HookConfig] =
  result = @[]
  for cfg in loader.configs:
    if cfg.phase == phase:
      if not onlyEnabled or cfg.enabled:
        result.add(cfg)

func parsePhaseStr*(s: string): Option[HookPhase] =
  case s
  of "pre_llm": some(hpPreLlm)
  of "post_llm": some(hpPostLlm)
  of "pre_tool": some(hpPreTool)
  of "post_tool": some(hpPostTool)
  of "post_response": some(hpPostResponse)
  else: none(HookPhase)

func parseHookConfig*(node: JsonNode): Option[HookConfig] =
  if node.kind != JObject:
    return none(HookConfig)
  
  let name = node.getOrDefault("name").getStr("")
  if name.len == 0:
    return none(HookConfig)
  
  let enabled = node.getOrDefault("enabled").getBool(true)
  let phaseStr = node.getOrDefault("phase").getStr("pre_llm")
  let phase = parsePhaseStr(phaseStr).get(hpPreLlm)
  
  var params = newStringTable(modeCaseInsensitive)
  let paramsNode = node.getOrDefault("params")
  if paramsNode.kind == JObject:
    for key, val in paramsNode.fields:
      params[key] = val.getStr("")
  
  some(HookConfig(
    name: name,
    enabled: enabled,
    phase: phase,
    params: params,
  ))

func parseHookConfigs*(node: JsonNode): seq[HookConfig] =
  result = @[]
  if node.kind == JArray:
    for item in node:
      let cfg = parseHookConfig(item)
      if cfg.isSome():
        result.add(cfg.get())
