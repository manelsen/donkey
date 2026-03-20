## Personality domain — agent identity, traits, and onboarding state.
##
## Pure functions (func). No I/O, no side effects.

import std/[options, sequtils, strutils]
export strutils, sequtils, options

# ── Types ─────────────────────────────────────────────────────────────────────

type
  PersonalityTraits* = object
    energy*:     string   ## "reservado" | "neutro" | "entusiasmado"
    tone*:       string   ## "formal" | "neutro" | "casual"
    length*:     string   ## "conciso" | "moderado" | "detalhado"
    initiative*: string   ## "reativo" | "moderado" | "proativo"

  DimensionKind* = enum
    dkEnergy, dkTone, dkLength, dkInitiative

  OnboardingPhase* = enum
    opWakeUp          ## agent just woke up, sends first message
    opModeChoice      ## waiting for Guided / Free choice
    opGuidedEnergy    ## collecting Energy dimension
    opGuidedTone      ## collecting Tone dimension
    opGuidedLength    ## collecting Length dimension
    opGuidedInitiative ## collecting Initiative dimension
    opFreeConvo       ## free-form identity conversation
    opNameChoice      ## waiting for user to pick a name
    opUserName        ## collecting user's name
    opUserTimezone    ## collecting user's timezone
    opUserLanguage    ## collecting user's preferred language
    opDone            ## onboarding complete

  OnboardingState* = object
    phase*:  OnboardingPhase
    traits*: PersonalityTraits
    names*:  seq[string]   ## generated name candidates

# ── Dimension metadata ─────────────────────────────────────────────────────────

const
  DimName = ["energy", "tone", "length", "initiative"]

  DimOptions: array[DimensionKind, array[3, (string, string)]] = [
    # dkEnergy
    [("Reservado", "reservado"), ("Neutro", "neutro"), ("Entusiasmado", "entusiasmado")],
    # dkTone
    [("Formal", "formal"), ("Neutro", "neutro"), ("Casual", "casual")],
    # dkLength
    [("Conciso", "conciso"), ("Moderado", "moderado"), ("Detalhado", "detalhado")],
    # dkInitiative
    [("Reativo", "reativo"), ("Moderado", "moderado"), ("Proativo", "proativo")],
  ]

  DimPrompt: array[DimensionKind, string] = [
    "Como devo me expressar em termos de energia e entusiasmo?",
    "Qual tom prefere nas minhas respostas?",
    "Como prefere que eu calibre o comprimento das minhas respostas?",
    "Devo agir por iniciativa própria ou esperar ser acionado?",
  ]

# ── Personality prompt ─────────────────────────────────────────────────────────

func buildPersonalityPrompt*(traits: PersonalityTraits; name: string): string =
  ## Builds a system-prompt fragment encoding the agent's personality.
  var lines: seq[string]

  if name.len > 0:
    lines.add("Your name is " & name & ".")

  # Energy
  let energyLine = case traits.energy
    of "reservado":    "Maintain a reserved, measured presence — moderate your enthusiasm and avoid excessive expressiveness."
    of "entusiasmado": "Express genuine enthusiasm and warmth in your responses — be energetic and engaged."
    else:              "Keep a balanced, neutral energy level."
  lines.add(energyLine)

  # Tone
  let toneLine = case traits.tone
    of "formal":  "Use formal language and maintain professional distance."
    of "casual":  "Be relaxed and conversational — use casual language as between friends."
    else:         "Use a neutral, adaptable tone."
  lines.add(toneLine)

  # Length
  let lengthLine = case traits.length
    of "conciso":   "Be concise — prefer short, direct answers. Omit what isn't strictly necessary."
    of "detalhado": "Be thorough and detailed — explain your reasoning and provide context."
    else:           "Calibrate response length to the complexity of the question."
  lines.add(lengthLine)

  # Initiative
  let initiativeLine = case traits.initiative
    of "reativo":  "Respond only to what is asked — do not volunteer unsolicited suggestions or topics."
    of "proativo": "Be proactive — anticipate follow-up needs and volunteer relevant context or suggestions."
    else:          "Balance responsiveness with occasional proactive observations when clearly useful."
  lines.add(initiativeLine)

  result = lines.join("\n")

# ── Name generation prompt ─────────────────────────────────────────────────────

func buildNameGenPrompt*(traits: PersonalityTraits): string =
  ## Returns a prompt asking the LLM to suggest 5 names matching the personality.
  "Given the following personality profile, suggest exactly 5 short names (one per line) " &
  "that feel fitting for an AI assistant with these traits:\n" &
  "- Energy: " & traits.energy & "\n" &
  "- Tone: " & traits.tone & "\n" &
  "- Response length: " & traits.length & "\n" &
  "- Initiative: " & traits.initiative & "\n\n" &
  "Output only the five names, one per line, no numbering, no explanation."

# ── parseNameOptions ───────────────────────────────────────────────────────────

func parseNameOptions*(resp: string): seq[string] =
  ## Extracts candidate names from an LLM response (one name per line).
  ## Ignores blank lines and leading/trailing whitespace.
  resp.splitLines
      .mapIt(it.strip)
      .filterIt(it.len > 0)

# ── parseIdentityReady / stripIdentityReady ────────────────────────────────────

const IdentityMarker = "IDENTITY_READY:"

func parseIdentityReady*(text: string): Option[PersonalityTraits] =
  ## Searches for an IDENTITY_READY: block in text and parses the key:value pairs.
  let lines = text.splitLines
  var idx = -1
  for i, l in lines:
    if l.strip == IdentityMarker:
      idx = i
      break
  if idx < 0:
    return none(PersonalityTraits)

  var t = PersonalityTraits()
  for i in (idx + 1) ..< lines.len:
    let l = lines[i].strip
    if l.len == 0:
      break                    ## blank line ends the block
    let parts = l.split(':', 1)
    if parts.len == 2:
      let k = parts[0].strip
      let v = parts[1].strip
      case k
      of "energy":     t.energy     = v
      of "tone":       t.tone       = v
      of "length":     t.length     = v
      of "initiative": t.initiative = v
      else: discard

  some(t)

func stripIdentityReady*(text: string): string =
  ## Returns the text with the IDENTITY_READY: block removed.
  ## Preserves content before and after the block.
  let lines = text.splitLines
  var markerIdx = -1
  for i, l in lines:
    if l.strip == IdentityMarker:
      markerIdx = i
      break
  if markerIdx < 0:
    return text

  # Find end of block: first blank line after marker
  var blockEnd = markerIdx + 1
  while blockEnd < lines.len and lines[blockEnd].strip.len > 0:
    inc blockEnd
  # skip the trailing blank line if present
  if blockEnd < lines.len and lines[blockEnd].strip.len == 0:
    inc blockEnd

  var kept: seq[string]
  for i, l in lines:
    if i >= markerIdx and i < blockEnd:
      continue
    kept.add(l)

  # Clean up any double blank lines left at the seam
  result = kept.join("\n").strip

# ── guidedDimensionMsg ─────────────────────────────────────────────────────────

func guidedDimensionMsg*(dk: DimensionKind): (string, seq[seq[(string, string)]]) =
  ## Returns (prompt text, inline keyboard rows) for a personality dimension.
  ## Keyboard has one row of 3 buttons; callback_data = "personality:<dim>:<valor>".
  let dim = DimName[ord(dk)]
  let opts = DimOptions[dk]
  let prompt = DimPrompt[dk]

  var row: seq[(string, string)]
  for (label, valor) in opts:
    row.add((label, "personality:" & dim & ":" & valor))

  (prompt, @[row])
