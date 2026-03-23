## graph_pure.nim — Triple Extraction Logic (Subject-Predicate-Object).
##
## Pure logic to parse Subject-Predicate-Object triples from text,
## in the style of knowledge graph construction from natural language.
##
## Usage:
##   text
##     |> extractTriples
##     |> filterValidTriples
##
##   text
##     |>-> extractTriplesWith(denyList = @["the", "a"])
##     |> mapIt(it.subject)

import std/[strutils, sequtils, algorithm]

type
  Triple*[T] = object
    ## A Subject-Predicate-Object triple with optional metadata.
    subject*: T
    predicate*: T
    obj*: T
    confidence*: float
    rawText*: string

  TripleText* = Triple[string]
    ## Triple with string values.

  TripleToken* = object
    ## A triple with normalized token values and positions.
    subject*: string
    predicate*: string
    obj*: string
    subjectSpan*: tuple[start, stop: int]
    predicateSpan*: tuple[start, stop: int]
    objectSpan*: tuple[start, stop: int]

const
  DefaultMinTripleLen* = 10
    ## Minimum text length to attempt extraction.

  DefaultMinConfidence* = 0.5
    ## Minimum confidence threshold for valid triples.

  # Common verb patterns for predicate detection
  VerbPatterns* = [
    "is", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "having",
    "do", "does", "did", "doing",
    "can", "could", "will", "would", "shall", "should", "may", "might", "must",
    "make", "made", "making",
    "take", "took", "taking",
    "give", "gave", "giving",
    "get", "got", "getting",
    "see", "saw", "seeing",
    "know", "knew", "knowing",
    "think", "thought", "thinking",
    "say", "said", "saying",
    "go", "went", "going",
    "come", "came", "coming",
    "want", "wanted", "wanting",
    "use", "used", "using",
    "find", "found", "finding",
    "tell", "told", "telling",
    "ask", "asked", "asking",
    "work", "worked", "working",
    "seem", "seemed", "seeming",
    "feel", "felt", "feeling",
    "try", "tried", "trying",
    "leave", "left", "leaving",
    "call", "called", "calling",
    "keep", "kept", "keeping",
    "let", "letting",
    "begin", "began", "beginning",
    "seem", "seemed", "seeming",
    "help", "helped", "helping",
    "show", "showed", "showing",
    "hear", "heard", "hearing",
    "play", "played", "playing",
    "run", "ran", "running",
    "move", "moved", "moving",
    "live", "lived", "living",
    "believe", "believed", "believing",
    "hold", "held", "holding",
    "bring", "brought", "bringing",
    "happen", "happened", "happening",
    "write", "wrote", "writing",
    "provide", "provided", "providing",
    "sit", "sat", "sitting",
    "stand", "stood", "standing",
    "lose", "lost", "losing",
    "pay", "paid", "paying",
    "meet", "met", "meeting",
    "include", "included", "including",
    "continue", "continued", "continuing",
    "set", "setting",
    "learn", "learned", "learning",
    "change", "changed", "changing",
    "lead", "led", "leading",
    "understand", "understood", "understanding",
    "watch", "watched", "watching",
    "follow", "followed", "following",
    "stop", "stopped", "stopping",
    "create", "created", "creating",
    "speak", "spoke", "speaking",
    "read", "reading",
    "spend", "spent", "spending",
    "grow", "grew", "growing",
    "open", "opened", "opening",
    "walk", "walked", "walking",
    "win", "won", "winning",
    "offer", "offered", "offering",
    "remember", "remembered", "remembering",
    "love", "loved", "loving",
    "consider", "considered", "considering",
    "appear", "appeared", "appearing",
    "buy", "bought", "buying",
    "wait", "waited", "waiting",
    "serve", "served", "serving",
    "die", "died", "dying",
    "send", "sent", "sending",
    "expect", "expected", "expecting",
    "build", "built", "building",
    "stay", "stayed", "staying",
    "fall", "fell", "falling",
    "cut", "cutting",
    "reach", "reached", "reaching",
    "kill", "killed", "killing",
    "remain", "remained", "remaining",
  ]

  # Common preposition patterns that indicate relationships
  PrepositionList* = @[
    "of", "in", "to", "for", "with", "on", "at", "from", "by", "about",
    "into", "through", "during", "before", "after", "above", "below",
    "between", "under", "again", "further", "then", "once"
  ]

  # Stopwords to filter from subjects/objects
  DefaultDenyList* = @[
    "the", "a", "an", "this", "that", "these", "those",
    "i", "you", "he", "she", "it", "we", "they",
    "my", "your", "his", "her", "its", "our", "their",
    "me", "him", "us", "them",
    "what", "which", "who", "whom", "whose",
    "is", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "having",
    "do", "does", "did", "doing",
    "will", "would", "could", "should", "may", "might", "must",
    "and", "but", "or", "nor", "so", "yet",
    "if", "then", "else", "when", "where", "why", "how",
    "all", "each", "every", "both", "few", "more", "most",
    "other", "some", "any", "no", "not", "only",
    "own", "same", "than", "too", "very",
    "just", "also", "now", "here", "there", "about"
  ]

func isStopword*(word: string; denyList: seq[string] = DefaultDenyList): bool =
  ## Checks if a word is in the deny list (case-insensitive).
  denyList.contains(word.toLowerAscii())

func isSignificantWord*(word: string; denyList: seq[string] = DefaultDenyList): bool =
  ## A word is significant if it's not empty, not purely punctuation,
  ## and not in the deny list.
  if word.len == 0:
    return false
  if word.allIt(it.isAlphaAscii()):
    return not isStopword(word, denyList)
  false

func tokenize*(text: string): seq[string] =
  ## Splits text into tokens (words and punctuation).
  ## Punctuation is preserved as separate tokens.
  if text.len == 0:
    return @[]
  var current = ""
  for ch in text:
    if ch.isAlphaAscii() or ch == '\'' or ch == '-':
      current.add(ch)
    else:
      if current.len > 0:
        result.add(current)
        current = ""
      if ch.isSpaceAscii():
        continue
      else:
        result.add($ch)
  if current.len > 0:
    result.add(current)

func normalizeEntity*(entity: string): string =
  ## Normalizes an entity string: lower case, trim, collapse spaces.
  entity.toLowerAscii().strip().split(' ').filterIt(it.len > 0).join(" ")

func isValidEntity*(entity: string): bool =
  ## Checks if an entity string is valid (non-empty, not just stopwords).
  let normalized = normalizeEntity(entity)
  if normalized.len == 0:
    return false
  let tokens = normalized.tokenize()
  tokens.anyIt(it.isSignificantWord())

func extractNounPhrasesSimple*(tokens: seq[string]): seq[(string, int, int)] =
  ## Extracts simple noun phrases as contiguous significant word sequences.
  ## Returns (phrase, startIndex, endIndex).
  var i = 0
  while i < tokens.len:
    if tokens[i].isSignificantWord():
      var start = i
      var phrase = ""
      while i < tokens.len and tokens[i].isSignificantWord():
        if phrase.len > 0:
          phrase.add(' ')
        phrase.add(tokens[i])
        inc i
      result.add((phrase, start, i - 1))
    else:
      inc i

func findPredicateBetween*(subject, obj: string; text: string): string =
  ## Finds the verb/predicate between two entities in the text.
  ## Returns the normalized predicate or empty string if not found.
  let subLower = subject.toLowerAscii()
  let objLower = obj.toLowerAscii()
  let textLower = text.toLowerAscii()

  let subPos = textLower.find(subLower)
  let objPos = textLower.find(objLower)

  if subPos < 0 or objPos < 0:
    return ""

  # Determine the order
  let (startPos, endPos) = if subPos < objPos:
    (subPos + subject.len, objPos)
  else:
    (objPos + obj.len, subPos)

  if endPos <= startPos:
    return ""

  let betweenText = text[startPos ..< endPos]

  # Look for verbs in the between text
  let tokens = betweenText.tokenize()
  for token in tokens:
    let normalized = token.toLowerAscii()
    if normalized in VerbPatterns:
      return normalized

  # Fall back to returning the between text if no verb found
  let trimmed = betweenText.strip()
  if trimmed.len > 0 and trimmed.len < 50:
    return normalizeEntity(trimmed)

  ""

func buildTriple*(subject, predicate, objValue: string; rawText: string; confidence: float): TripleText =
  ## Builds a TripleText with the given components.
  TripleText(
    subject: normalizeEntity(subject),
    predicate: normalizeEntity(predicate),
    obj: normalizeEntity(objValue),
    confidence: confidence,
    rawText: rawText
  )

func extractBePatternTriples*(sentence: string; denyList: seq[string] = DefaultDenyList): seq[TripleText] =
  ## Extracts "X is/are/was/were Y" triples.
  let s = sentence.toLowerAscii()
  for beVerb in ["is", "are", "was", "were"]:
    let idx = s.find(" " & beVerb & " ")
    if idx >= 0:
      let before = sentence[0 ..< idx].strip()
      let afterStart = idx + beVerb.len + 2
      if afterStart < sentence.len:
        var after = sentence[afterStart .. ^1].strip()
        # Strip leading "a/an/the"
        if after.startsWith("a ") or after.startsWith("an ") or after.startsWith("the "):
          let spaceIdx = after.find(' ')
          if spaceIdx >= 0:
            after = after[spaceIdx + 1 .. ^1].strip()
        if isValidEntity(before) and isValidEntity(after):
          result.add(buildTriple(before, beVerb, after, sentence, 0.9))

func extractTriplesFromSentence*(sentence: string; denyList: seq[string] = DefaultDenyList): seq[TripleText] =
  ## Extracts S-P-O triples from a single sentence using pattern matching.
  ##
  ## Patterns detected:
  ## - "X is/are/was/were [a/an] Y" → X, "is", Y
  ## - "X VERB Y" → X, VERB, Y
  ## - "X preposition Y" → X, preposition, Y

  if sentence.len < DefaultMinTripleLen:
    return @[]

  # Extract be-pattern triples first
  result.add(extractBePatternTriples(sentence, denyList))

  # Pattern: "X VERB Y" where VERB is a known verb
  let nounPhrases = extractNounPhrasesSimple(tokenize(sentence))
  for i, (subj, _, _) in nounPhrases:
    for j, (objPart, _, _) in nounPhrases:
      if i < j:
        let pred = findPredicateBetween(subj, objPart, sentence)
        if pred.len > 0:
          let conf = if pred in VerbPatterns: 0.8 else: 0.6
          result.add(buildTriple(subj, pred, objPart, sentence, conf))

  # Pattern: "X preposition Y" (relationships)
  let sentenceLower = sentence.toLowerAscii()
  for prep in PrepositionList:
    if sentenceLower.contains(prep):
      # Simple preposition-based extraction
      for i, (subj, _, _) in nounPhrases:
        for j, (objPart, _, _) in nounPhrases:
          if i < j:
            let pred = findPredicateBetween(subj, objPart, sentence)
            if pred.len > 0 and pred == prep:
              result.add(buildTriple(subj, prep, objPart, sentence, 0.7))

func extractTriples*(text: string; denyList: seq[string] = DefaultDenyList): seq[TripleText] =
  ## Extracts Subject-Predicate-Object triples from text.
  ##
  ## Splits text into sentences and extracts triples from each.
  ## Uses `|>` for chaining:
  ##   text |> extractTriples |> filterByConfidence(0.7)
  if text.len == 0:
    return @[]

  # Split into sentences (simple period-based split)
  let sentences = text.split('.')
  for sent in sentences:
    let trimmed = sent.strip()
    if trimmed.len >= DefaultMinTripleLen:
      let triples = extractTriplesFromSentence(trimmed, denyList)
      result.add(triples)

func extractTriplesWith*(text: string; denyList: seq[string]): seq[TripleText] =
  ## Extracts triples with a custom deny list.
  text.extractTriples(denyList)

func filterByConfidence*(triples: seq[TripleText]; threshold: float): seq[TripleText] =
  ## Filters triples by minimum confidence threshold.
  ## Uses `|>` chaining: triples |> filterByConfidence(0.7)
  triples.filterIt(it.confidence >= threshold)

func filterValidTriples*(triples: seq[TripleText]): seq[TripleText] =
  ## Filters out triples with empty/invalid components.
  triples.filterIt(
    it.subject.len > 0 and
    it.predicate.len > 0 and
    it.obj.len > 0 and
    it.confidence >= DefaultMinConfidence
  )

func deduplicateTriples*(triples: seq[TripleText]): seq[TripleText] =
  ## Removes duplicate triples (same subject, predicate, object).
  var seen: seq[string] = @[]
  var unique: seq[TripleText] = @[]
  for triple in triples:
    let key = triple.subject & "|" & triple.predicate & "|" & triple.obj
    if key notin seen:
      seen.add(key)
      unique.add(triple)
  unique

func sortByConfidence*(triples: seq[TripleText]; descending: bool = true): seq[TripleText] =
  ## Sorts triples by confidence score.
  if descending:
    sorted(triples, proc(a, b: TripleText): int =
      cmp(b.confidence, a.confidence))
  else:
    sorted(triples, proc(a, b: TripleText): int =
      cmp(a.confidence, b.confidence))

func extractSubjects*(triples: seq[TripleText]): seq[string] =
  ## Extracts all unique subjects from triples.
  var seen: seq[string] = @[]
  for triple in triples:
    if triple.subject notin seen:
      seen.add(triple.subject)
  seen

func extractPredicates*(triples: seq[TripleText]): seq[string] =
  ## Extracts all unique predicates from triples.
  var seen: seq[string] = @[]
  for triple in triples:
    if triple.predicate notin seen:
      seen.add(triple.predicate)
  seen

func extractObjects*(triples: seq[TripleText]): seq[string] =
  ## Extracts all unique objects from triples.
  var seen: seq[string] = @[]
  for triple in triples:
    if triple.obj notin seen:
      seen.add(triple.obj)
  seen

func triplesToText*(triples: seq[TripleText]): string =
  ## Converts triples to a readable text representation.
  ## Each triple on its own line: "SUBJECT — PREDICATE → OBJECT"
  for triple in triples:
    if result.len > 0:
      result.add("\n")
    result.add(triple.subject & " — " & triple.predicate & " → " & triple.obj)

func tripleCount*(triples: seq[TripleText]): tuple[total, valid, unique: int] =
  ## Returns counts: total triples, valid triples, unique triples.
  let valid = filterValidTriples(triples)
  let unique = deduplicateTriples(valid)
  (triples.len, valid.len, unique.len)
