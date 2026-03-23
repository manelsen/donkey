## Tests for graph_pure.nim — Triple Extraction Logic.

import std/[unittest, strutils, sequtils]
import donkey/domain/memory/graph_pure

suite "graph_pure - Triple Extraction Logic":

  # --- Tokenization ---

  test "tokenize splits on spaces":
    let tokens = "hello world".tokenize
    check tokens == @["hello", "world"]

  test "tokenize handles punctuation":
    let tokens = "hello, world!".tokenize
    check tokens == @["hello", ",", "world", "!"]

  test "tokenize handles contractions":
    let tokens = "don't go".tokenize
    check tokens == @["don't", "go"]

  test "tokenize empty string":
    let tokens: seq[string] = "".tokenize
    check tokens.len == 0

  test "tokenize preserves hyphens":
    let tokens = "well-known fact".tokenize
    check tokens == @["well-known", "fact"]

  # --- Stopword detection ---

  test "isStopword detects common stopwords":
    check isStopword("the") == true
    check isStopword("The") == true
    check isStopword("and") == true
    check isStopword("is") == true

  test "isStopword allows significant words":
    check isStopword("computer") == false
    check isStopword("algorithm") == false
    check isStopword("Donkey") == false

  test "isSignificantWord rejects empty":
    check isSignificantWord("") == false

  test "isSignificantWord rejects only stopwords":
    check isSignificantWord("the a an") == false

  test "isSignificantWord accepts significant words":
    check isSignificantWord("computer") == true
    check isSignificantWord("algorithm") == true

  # --- Entity normalization ---

  test "normalizeEntity lowercases":
    check normalizeEntity("Hello World") == "hello world"

  test "normalizeEntity trims":
    check normalizeEntity("  hello  ") == "hello"

  test "normalizeEntity collapses spaces":
    check normalizeEntity("hello   world") == "hello world"

  test "normalizeEntity empty":
    check normalizeEntity("   ") == ""
    check normalizeEntity("") == ""

  test "isValidEntity accepts valid":
    check isValidEntity("computer") == true
    check isValidEntity("The Computer") == true
    check isValidEntity("machine learning") == true

  test "isValidEntity rejects empty":
    check isValidEntity("") == false
    check isValidEntity("   ") == false

  test "isValidEntity rejects stopwords":
    check isValidEntity("the") == false
    check isValidEntity("a") == false

  # --- Noun phrase extraction ---

  test "extractNounPhrasesSimple finds phrases":
    let tokens = @["the", "computer", "is", "fast"]
    let phrases = extractNounPhrasesSimple(tokens)
    check phrases.len == 2
    check phrases[0][0] == "computer"
    check phrases[1][0] == "fast"

  test "extractNounPhrasesSimple empty input":
    let phrases = extractNounPhrasesSimple(@[])
    check phrases.len == 0

  test "extractNounPhrasesSimple spans":
    let tokens = @["machine", "learning", "is", "powerful"]
    let phrases = extractNounPhrasesSimple(tokens)
    check phrases.len == 2
    check phrases[0][1] == 0  # start index
    check phrases[0][2] == 1  # end index

  # --- Predicate finding ---

  test "findPredicateBetween detects verb":
    let pred = findPredicateBetween("computer", "fast", "The computer is fast")
    check pred == "is"

  test "findPredicateBetween no match":
    let pred = findPredicateBetween("cat", "dog", "The cat is here")
    check pred == ""

  test "findPredicateBetween returns between text as fallback":
    let pred = findPredicateBetween("fast", "computer", "fast than computer")
    check pred == "than"  # Falls back to between text when no verb found

  # --- Triple building ---

  test "buildTriple creates valid triple":
    let triple = buildTriple("Computer", "is", "fast", "The computer is fast", 0.9)
    check triple.subject == "computer"
    check triple.predicate == "is"
    check triple.obj == "fast"
    check triple.confidence == 0.9
    check triple.rawText == "The computer is fast"

  # --- Sentence extraction ---

  test "extractTriplesFromSentence finds be-pattern":
    let triples = extractTriplesFromSentence("Donkey is an AI agent")
    check triples.len >= 1
    let found = triples.anyIt(it.subject == "donkey" and it.predicate == "is")
    check found == true

  test "extractTriplesFromSentence short sentence returns empty":
    let triples = extractTriplesFromSentence("Short.")
    check triples.len == 0

  test "extractTriplesFromSentence no valid entities":
    let triples = extractTriplesFromSentence("the is a an")
    check triples.len == 0

  # --- Full text extraction ---

  test "extractTriples handles empty":
    let triples = "".extractTriples
    check triples.len == 0

  test "extractTriples splits sentences":
    let triples = "Donkey is an AI agent. Computer is fast.".extractTriples
    check triples.len >= 2

  test "extractTriples with custom denyList":
    let triples = "The machine is learning".extractTriplesWith(@["the", "machine"])
    check triples.filterIt(it.subject == "learning").len == 0

  # --- Filtering ---

  test "filterByConfidence removes low confidence":
    var triples = @[buildTriple("a", "b", "c", "", 0.3),
                    buildTriple("a", "b", "c", "", 0.7),
                    buildTriple("a", "b", "c", "", 0.9)]
    triples = triples.filterByConfidence(0.7)
    check triples.len == 2
    check triples.allIt(it.confidence >= 0.7)

  test "filterValidTriples removes invalid":
    var triples = @[
      buildTriple("", "is", "valid", "", 0.5),
      buildTriple("subject", "", "object", "", 0.5),
      buildTriple("subject", "pred", "", "", 0.5),
      buildTriple("subject", "pred", "object", "", 0.3),  # low confidence
      buildTriple("subject", "pred", "object", "", 0.8),
    ]
    triples = triples.filterValidTriples
    check triples.len == 1
    check triples[0].subject == "subject"

  test "deduplicateTriples removes duplicates":
    var triples = @[
      buildTriple("a", "b", "c", "", 0.9),
      buildTriple("a", "b", "c", "", 0.5),
      buildTriple("a", "x", "c", "", 0.9),
    ]
    triples = triples.deduplicateTriples
    check triples.len == 2

  test "sortByConfidence descending":
    var triples = @[
      buildTriple("a", "b", "c", "", 0.3),
      buildTriple("a", "b", "c", "", 0.9),
      buildTriple("a", "b", "c", "", 0.6),
    ]
    triples = triples.sortByConfidence(descending = true)
    check triples[0].confidence == 0.9
    check triples[1].confidence == 0.6
    check triples[2].confidence == 0.3

  # --- Extraction helpers ---

  test "extractSubjects gets unique":
    var triples = @[
      buildTriple("subject1", "pred", "obj", "", 0.9),
      buildTriple("subject2", "pred", "obj", "", 0.9),
      buildTriple("subject1", "pred", "obj", "", 0.9),  # duplicate
    ]
    let subjects = triples.extractSubjects
    check subjects.len == 2
    check "subject1" in subjects
    check "subject2" in subjects

  test "extractPredicates gets unique":
    var triples = @[
      buildTriple("subj", "pred1", "obj", "", 0.9),
      buildTriple("subj", "pred2", "obj", "", 0.9),
    ]
    let preds = triples.extractPredicates
    check preds.len == 2

  test "extractObjects gets unique":
    var triples = @[
      buildTriple("subj", "pred", "obj1", "", 0.9),
      buildTriple("subj", "pred", "obj2", "", 0.9),
      buildTriple("subj", "pred", "obj1", "", 0.9),  # duplicate
    ]
    let objs = triples.extractObjects
    check objs.len == 2

  # --- Output formatting ---

  test "triplesToText formats correctly":
    var triples = @[
      buildTriple("computer", "is", "fast", "", 0.9),
      buildTriple("ai", "uses", "data", "", 0.8),
    ]
    let text = triples.triplesToText
    check text.contains("computer — is → fast")
    check text.contains("ai — uses → data")

  test "tripleCount returns counts":
    var triples = @[
      buildTriple("a", "b", "c", "", 0.9),
      buildTriple("a", "b", "c", "", 0.5),  # duplicate
      buildTriple("", "b", "c", "", 0.5),  # invalid
    ]
    let (total, valid, unique) = tripleCount(triples)
    check total == 3
    check valid == 2  # one filtered by empty subject
    check unique == 1  # one duplicate

  # --- Chaining with |> ---

  test "pipe chain works end-to-end":
    let text = "Donkey is an AI agent. Computer is fast. Data is important."
    let triples = text.extractTriples.filterValidTriples.deduplicateTriples.sortByConfidence
    check triples.len > 0
    check triples[0].confidence >= triples[^1].confidence

  test "filterByConfidence can be piped":
    var triples = @[
      buildTriple("a", "b", "c", "", 0.2),
      buildTriple("a", "b", "c", "", 0.8),
    ]
    let filtered = filterByConfidence(triples, 0.5)
    check filtered.len == 1
    check filtered[0].confidence == 0.8
