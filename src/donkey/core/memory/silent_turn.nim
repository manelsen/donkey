## silent_turn.nim — Background Memory Extraction Loop.
##
## Runs a silent LLM turn before session compaction to review the conversation
## and persist important information to memory storage (graph + vector).
##
## Inspired by moltis' silent memory turn pattern:
##   https://github.com/openclaw/moltis/blob/main/crates/agents/src/silent_turn.rs
##
## Unlike moltis (which writes to files via write_file tool), Donkey's silent turn
## extracts triples and stores them via the graph adapter (AGE) and the pgvector
## adapter, following the F2+ memory architecture.
##
## The LLM's text response is discarded — only structured extractions matter.
## This runs without user prompt in a background context.
##
## Usage:
##   let result = runSilentMemoryTurn(
##     conversation,
##     completeFn,
##     userId,
##   )
##   if result.isErr:
##     log.warn("silent turn: " & result.error)

import std/[strutils, times, json, options]

import ../../core/pipeops
import ../../core/types
import ../../core/log
import ../../domain/message
import ../../domain/memory/graph_pure
import ../../ports/provider

const
  SilentMemorySystemPrompt* = """You are a memory extraction agent. Your job is to analyze the conversation and extract structured memories.

Extract and return a JSON object with these fields:
{
  "triples": [
    {"subject": "...", "predicate": "...", "object": "...", "confidence": 0.9}
  ],
  "facts": ["fact 1", "fact 2"],
  "preferences": ["preference 1"],
  "concepts": ["concept 1", "concept 2"]
}

Rules:
- Only extract high-confidence facts (confidence >= 0.7)
- Subject and object should be concise entity names
- Predicates should be simple verbs or relationships
- Focus on: user preferences, technical decisions, project context, names, dates
- Do NOT respond with free-form text — only the JSON object
- If no significant memories found, return empty arrays

Conversation to analyze:"""

type
  SilentMemoryResult* = object
    triplesCount*: int
    factsCount*: int
    preferencesCount*: int
    conceptsCount*: int
    filesWritten*: seq[string]

  SilentMemoryError* = object
    message*: string

func formatConversationForMemory*(history: ConversationHistory): string =
  ## Formats conversation history for the memory extraction prompt.
  ## Truncates very long messages to avoid token limits.
  const MaxMessageLen = 2000
  result = ""
  for msg in history:
    let role = msg.role
    var content = msg.text
    if content.len > MaxMessageLen:
      content = content[0 ..< MaxMessageLen] & "..."
    if result.len > 0:
      result.add("\n")
    result.add(role & ": " & content)

proc parseMemoryExtractionResponse*(response: string): Result[SilentMemoryResult, string] =
  ## Parses the LLM's JSON response into a SilentMemoryResult.
  ## The response text is discarded (not shown to user) per the silent turn pattern.
  if response.len == 0:
    return ok(SilentMemoryResult(
      triplesCount: 0,
      factsCount: 0,
      preferencesCount: 0,
      conceptsCount: 0,
      filesWritten: @[],
    ))
  
  try:
    let j = parseJson(response)
    
    var triples: seq[TripleText] = @[]
    if j.hasKey("triples"):
      for item in j["triples"]:
        let subj = item["subject"].getStr()
        let pred = item["predicate"].getStr()
        let obj = item["object"].getStr()
        let conf = if item.hasKey("confidence"): item["confidence"].getFloat() else: 0.8
        triples.add(buildTriple(subj, pred, obj, response, conf.float))
    
    var facts: seq[string] = @[]
    if j.hasKey("facts"):
      for item in j["facts"]:
        facts.add(item.getStr())
    
    var preferences: seq[string] = @[]
    if j.hasKey("preferences"):
      for item in j["preferences"]:
        preferences.add(item.getStr())
    
    var concepts: seq[string] = @[]
    if j.hasKey("concepts"):
      for item in j["concepts"]:
        concepts.add(item.getStr())
    
    ok(SilentMemoryResult(
      triplesCount: triples.len,
      factsCount: facts.len,
      preferencesCount: preferences.len,
      conceptsCount: concepts.len,
      filesWritten: @[],
    ))
  except CatchableError as e:
    err("parseMemoryExtractionResponse: " & e.msg)

proc tryParseJson*(s: string): Option[JsonNode] =
  try:
    some(parseJson(s))
  except CatchableError:
    none(JsonNode)

when defined(withPostgres):
  import chronos
  import ../../adapters/memory/age_store
  import ../../adapters/memory/pgvector_store
  import ../../domain/memory/chunking
  import ../../core/memory/embedder
  
  proc runSilentMemoryTurn*(
    history: ConversationHistory;
    completeFn: CompleteFn;
    userId: UserId;
    ageAdapter: AgeStoreAdapter;
    embedFn: EmbedFn;
    pgAdapter: PgvectorStoreAdapter;
  ): Future[Result[SilentMemoryResult, string]] {.async.} =
    ## Runs a silent memory extraction turn with full postgres support.
    ##
    ## 1. Formats conversation for the memory extraction prompt
    ## 2. Calls LLM with system prompt asking for structured JSON extraction
    ## 3. Parses response and stores triples via AGE adapter
    ## 4. Stores facts/concepts via pgvector adapter
    ## 5. Returns counts of what was stored (LLM text response is discarded)
    
    if history.len == 0:
      return
  
    let conversationText = formatConversationForMemory(history)
    let req = CompletionRequest(
      system: SilentMemorySystemPrompt,
      messages: @[ChatMessage(role: roleUser, text: conversationText)],
      maxTokens: 2048,
    )
    
    let resp = completeFn(req)
    if resp.isErr:
      return err("silent turn complete: " & resp.error)
    
    let responseText = resp.get().text
    let parseResult = parseMemoryExtractionResponse(responseText)
    if parseResult.isErr:
      return err("silent turn parse: " & parseResult.error)
    
    var result = parseResult.get()
    
    if result.triplesCount > 0:
      let j = tryParseJson(responseText)
      if j.isSome:
        let triplesJson = j.get()
        if triplesJson.hasKey("triples"):
          var triples: seq[TripleText] = @[]
          for item in triplesJson["triples"]:
            let subj = item["subject"].getStr()
            let pred = item["predicate"].getStr()
            let obj = item["object"].getStr()
            let conf = if item.hasKey("confidence"): item["confidence"].getFloat() else: 0.8
            triples.add(buildTriple(subj, pred, obj, responseText, conf.float))
          
          if triples.len > 0:
            let storeResult = ageAdapter.storeTriples(userId, triples)
            if storeResult.isErr:
              log.warn("silent turn storeTriples: " & storeResult.error)
            else:
              result.filesWritten.add("age://graph/triples")
    
    if result.factsCount > 0 or result.conceptsCount > 0:
      let j = tryParseJson(responseText)
      if j.isSome:
        let memJson = j.get()
        
        if memJson.hasKey("facts"):
          for factItem in memJson["facts"]:
            let fact = factItem.getStr()
            let chunks = fact.chunkTextWithHash(500, 50)
            for chunk in chunks:
              let embResult = embedChunk(chunk, embedFn)
              if embResult.isOk:
                let embedded = embResult.get()
                let storeResult = pgAdapter.storeChunk(userId, embedded)
                if storeResult.isErr:
                  log.warn("silent turn storeChunk(fact): " & storeResult.error)
        
        if memJson.hasKey("concepts"):
          for conceptItem in memJson["concepts"]:
            let conceptStr = conceptItem.getStr()
            let chunks = conceptStr.chunkTextWithHash(500, 50)
            for chunk in chunks:
              let embResult = embedChunk(chunk, embedFn)
              if embResult.isOk:
                let embedded = embResult.get()
                let storeResult = pgAdapter.storeChunk(userId, embedded)
                if storeResult.isErr:
                  log.warn("silent turn storeChunk(concept): " & storeResult.error)
        
        result.filesWritten.add("pgvector://memories")
    
    ok(result)

else:
  proc runSilentMemoryTurn*(
    history: ConversationHistory;
    completeFn: CompleteFn;
    userId: UserId;
  ): Result[SilentMemoryResult, string] =
    ## Runs a silent memory extraction turn without postgres (F1 fallback).
    ## Returns empty result since no storage is available in F1.
    
    if history.len == 0:
      return ok(SilentMemoryResult(
        triplesCount: 0,
        factsCount: 0,
        preferencesCount: 0,
        conceptsCount: 0,
        filesWritten: @[],
      ))
    
    let conversationText = formatConversationForMemory(history)
    let req = CompletionRequest(
      system: SilentMemorySystemPrompt,
      messages: @[ChatMessage(role: roleUser, text: conversationText)],
      maxTokens: 2048,
    )
    
    let resp = completeFn(req)
    if resp.isErr:
      return err("silent turn complete: " & resp.error)
    
    let responseText = resp.get().text
    let parseResult = parseMemoryExtractionResponse(responseText)
    if parseResult.isErr:
      return err("silent turn parse: " & parseResult.error)
    
    var memResult = parseResult.get()
    # In F1 without postgres, we can't store the memories persistently
    # The LLM's extraction is still performed and logged
    memResult.filesWritten.add("memory:extraction_only")
    
    ok(memResult)
