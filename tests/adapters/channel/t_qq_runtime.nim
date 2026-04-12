import std/[strutils, unittest]
import donkey/core/commands/command_routing
import donkey/adapters/channel/common_runtime
import donkey/adapters/channel/qq_runtime
import donkey/adapters/channel/qq_channel

suite "qq_runtime":

  test "qqHelpText reflects backend UX level":
    check qqHelpText(qbkOfficial).contains("- `/models` seleciona o modelo de IA")
    check qqHelpText(qbkOfficial).contains("- `/budget` controla a policy de custo/qualidade")
    check qqHelpText(qbkOfficial).contains("- `/skill` busca, instala e habilita skills")
    check qqHelpText(qbkOneBot).contains("/models [provider model] — vê ou troca o modelo de IA")

  test "qqDirectModelProvider opens rich picker only for official provider-only command":
    let providerCmd = parseCommandText("/models anthropic")
    let fullCmd = parseCommandText("/models anthropic claude-sonnet-4-6")
    check qqDirectModelProvider(qbkOfficial, providerCmd) == "anthropic"
    check qqDirectModelProvider(qbkOfficial, fullCmd) == ""
    check qqDirectModelProvider(qbkOneBot, providerCmd) == ""

  test "qqShouldOpenThinkPicker is only true for official bare /think":
    check qqShouldOpenThinkPicker(qbkOfficial, parseCommandText("/think"))
    check not qqShouldOpenThinkPicker(qbkOfficial, parseCommandText("/think high"))
    check not qqShouldOpenThinkPicker(qbkOneBot, parseCommandText("/think"))

  test "qq rich text helpers format picker and confirmation copy":
    let catalog = emptyCatalogResult()
    check qqProviderPickerTitle().contains("## Escolha o provider")
    check qqThinkPickerTitle().contains("## Nível de raciocínio")
    check qqModelPickerTitle("groq", 0, @[], catalog).contains("## Modelos de groq")
    check qqModelConfirmedText("groq", "llama-3.1-8b-instant").contains("**groq / llama-3.1-8b-instant**")
    check qqThinkingConfirmedText("high").contains("**high**")

  test "qq rich help and status use markdown structure":
    let help = qqHelpText(qbkOfficial)
    let status = qqStatusText("Provider: groq / llama-3.1-8b-instant", "high", 7, 2, "15m")
    check help.contains("## Donkey")
    check help.contains("- `/models` seleciona o modelo de IA")
    check help.contains("- `/budget` controla a policy de custo/qualidade")
    check status.contains("## Status")
    check status.contains("**groq / llama-3.1-8b-instant**")
    check status.contains("**15m**")
