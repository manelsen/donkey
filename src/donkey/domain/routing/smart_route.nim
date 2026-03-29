## Smart Routing Classifier — pure task complexity classification.
##
## This module turns request signals into an explicit complexity classification,
## enabling cost-aware provider selection. All functions are pure and use pipeops.
##
## Usage:
##   signals
##     |> classifyTaskComplexity
##     |> routeByComplexity(availability, prefs.budgetPolicy)

import std/[algorithm, strutils]
import ../../core/pipeops
import ../../core/providers/smart_routing
import ../../domain/message

export smart_routing

const
  SimpleMaxChars* = 2_000
  ModerateMaxChars* = 20_000

type
  TaskComplexity* = enum
    tcSimple
    tcModerate
    tcComplex

  ComplexityScore* = object
    complexity*: TaskComplexity
    inputScore*: int      ## 0-100: length/compression complexity
    toolScore*: int       ## 0-100: tool-calling and thinking complexity
    contextScore*: int    ## 0-100: multimodal/context window complexity
    rawChars*: int        ## Raw character count for reference

func complexityName*(tc: TaskComplexity): string =
  case tc
  of tcSimple: "simple"
  of tcModerate: "moderate"
  of tcComplex: "complex"

func scoreInputComplexity*(chars: int): int =
  ## Scores input complexity 0-100 based on character count.
  ## Short inputs = low complexity, long = high.
  let capped = min(chars, LongContextChars)
  (capped * 100) div LongContextChars

func scoreToolComplexity*(hasTools: bool; thinking: string): int =
  ## Scores tool-calling complexity 0-100.
  ## Tool use adds 50pts, thinking preference adds up to 50pts.
  var score = 0
  if hasTools:
    score += 50
  case thinking.normalizeThinking
  of "high": score += 50
  of "medium": score += 25
  else: discard
  score

func scoreContextComplexity*(chars: int; hasImage: bool): int =
  ## Scores context complexity 0-100.
  ## Images add 60pts, long context adds proportionally.
  let capped = min(chars, LongContextChars)
  let baseScore = (capped * 40) div LongContextChars
  if hasImage:
    min(baseScore + 60, 100)
  else:
    baseScore

func computeOverallComplexity*(input, tool, context: int): TaskComplexity =
  ## Combines three dimension scores into an overall complexity classification.
  ## Weights: tool 40%, input 30%, context 30%.
  let weighted = ((tool * 40) + (input * 30) + (context * 30)) div 100
  if weighted < 35:
    tcSimple
  elif weighted < 70:
    tcModerate
  else:
    tcComplex

# Internal helpers for provider availability checking
func providerIsAvailable*(av: ProviderAvailability; name: string): bool =
  case name
  of "openrouter": av.openrouter
  of "anthropic": av.anthropic
  of "gemini": av.gemini
  of "minimax": av.minimax
  of "zai": av.zai
  of "zai-coding": av.zaiCoding
  else: false

func addIfAvailable*(candidates: var seq[ProviderSelection];
                     av: ProviderAvailability;
                     providerName: string;
                     modelName = "") =
  if av.providerIsAvailable(providerName):
    candidates.add(ProviderSelection(
      providerName: providerName,
      modelName: if modelName.len > 0: modelName else: defaultModelForProvider(providerName),
    ))

func classifyTaskComplexity*(signals: RoutingSignals): ComplexityScore =
  ## Classifies a task's complexity from routing signals.
  ## All dimensions score 0-100; higher = more complex.
  let inputS = signals.approxInputChars |> scoreInputComplexity
  let toolS = scoreToolComplexity(signals.hasTools, signals.thinking)
  let ctxScore = signals.approxInputChars.scoreContextComplexity(signals.hasImage)

  ComplexityScore(
    complexity: computeOverallComplexity(inputS, toolS, ctxScore),
    inputScore: inputS,
    toolScore: toolS,
    contextScore: ctxScore,
    rawChars: signals.approxInputChars,
  )

func classifyTaskComplexity*(prefs: SmartRoutingPrefs;
                             req: CompletionRequest): ComplexityScore =
  ## Convenience: builds signals and classifies in one step.
  let signals = buildRoutingSignals(prefs, req)
  signals.classifyTaskComplexity

func routeByComplexity*(score: ComplexityScore;
                        availability: ProviderAvailability;
                        budgetPolicy: string): seq[ProviderSelection] =
  ## Selects and orders provider candidates based on task complexity.
  ## Uses budget policy to determine cost-quality tradeoff.
  let normalizedBudget = budgetPolicy.normalizeBudgetPolicy

  # Build candidate list based on complexity level
  var candidates: seq[ProviderSelection] = @[]

  case score.complexity
  of tcSimple:
    # Prefer cheap/fast providers
    candidates.addIfAvailable(availability, "minimax", "MiniMax-M2")
    candidates.addIfAvailable(availability, "openrouter", "openai/gpt-4o-mini")
    candidates.addIfAvailable(availability, "zai", "glm-4.7")
    candidates.addIfAvailable(availability, "gemini", "gemini-2.5-flash")
    if normalizedBudget == "quality-first":
      candidates.addIfAvailable(availability, "anthropic", "claude-sonnet-4-6")
  of tcModerate:
    # Balanced providers
    candidates.addIfAvailable(availability, "zai-coding", "glm-4.7")
    candidates.addIfAvailable(availability, "openrouter", "openai/gpt-4o-mini")
    candidates.addIfAvailable(availability, "gemini", "gemini-2.5-flash")
    candidates.addIfAvailable(availability, "anthropic", "claude-sonnet-4-6")
    if normalizedBudget == "cheap-first":
      candidates.addIfAvailable(availability, "minimax", "MiniMax-M2")
  of tcComplex:
    # Prefer capable providers
    if score.toolScore > 50 or score.contextScore > 60:
      # Tool-heavy or context-heavy -> use best tool providers
      candidates.addIfAvailable(availability, "anthropic", "claude-opus-4-6")
      candidates.addIfAvailable(availability, "zai-coding", "glm-5")
      candidates.addIfAvailable(availability, "gemini", "gemini-2.5-pro")
      candidates.addIfAvailable(availability, "openrouter", "openai/gpt-4o")
    else:
      # General complexity
      candidates.addIfAvailable(availability, "anthropic", "claude-opus-4-6")
      candidates.addIfAvailable(availability, "gemini", "gemini-2.5-pro")
      candidates.addIfAvailable(availability, "zai-coding", "glm-5")
      candidates.addIfAvailable(availability, "openrouter", "openai/gpt-4o")

  # Dedupe and return
  candidates.dedupeSelections

func complexityLabel*(score: ComplexityScore): string =
  ## Human-readable complexity summary.
  "(" & score.complexity.complexityName & ", input=" & $score.inputScore & ", tool=" & $score.toolScore & ", context=" & $score.contextScore & ")"

func classifyAndRoute*(prefs: SmartRoutingPrefs;
                       req: CompletionRequest;
                       availability: ProviderAvailability): tuple[score: ComplexityScore; selections: seq[ProviderSelection]] =
  ## Full classification + routing pipeline.
  let score = prefs.classifyTaskComplexity(req)
  let selections = score.routeByComplexity(availability, prefs.budgetPolicy)
  (score, selections)
