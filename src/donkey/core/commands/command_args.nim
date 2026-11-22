## Command arguments and the values they range over: thinking levels,
## budget policies, and how /think, /budget and /reasoning read and change
## them. Pure; the answers live in `command_text` and `preference_commands`.

import std/strutils
import ../pipeops
import ../providers/smart_routing

const
  ThinkLevels* = ["off", "low", "medium", "high"]
  BudgetPolicies* = ["cheap-first", "balanced", "quality-first"]

func parseThinkArgs*(value: string): Result[string, string] =
  let level = value.strip.toLowerAscii()
  if level.len == 0:
    return err("Use `/think <off|low|medium|high>`.")
  if level notin ThinkLevels:
    return err("Nível inválido: `" & level & "`.")
  ok(level)

func parseBudgetArgs*(value: string): Result[string, string] =
  let policy = normalizeBudgetPolicy(value)
  if value.strip.len == 0:
    return err("Use `/budget <cheap-first|balanced|quality-first>`.")
  if policy != value.strip.toLowerAscii():
    return err("Policy inválida: `" & value.strip & "`.")
  ok(policy)

func nextReasoning*(current: string): string =
  if current == "on": "off" else: "on"
