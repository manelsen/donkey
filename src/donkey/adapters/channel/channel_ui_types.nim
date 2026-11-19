## Shared constants and types for the channel UI helpers.
##
## Kept dependency-free so the preference and catalog modules can use them
## without importing the interactive UI layer.

const ThinkLevels* = ["off", "low", "medium", "high"]
const BudgetPolicies* = ["cheap-first", "balanced", "quality-first"]
const ModelPageSize* = 6  ## Discord: máx 5 action rows. 6 modelos / 2 por row = 3 rows + 1 nav = 4 rows (seguro)
const UiSlotMenu* = "menu"
const UiSlotConfig* = "config"
const UiSlotModels* = "models"
const UiSlotThink* = "think"
const UiSlotHelp* = "help"

type ModelMenuEntry* = tuple[provider: string, models: seq[string]]
