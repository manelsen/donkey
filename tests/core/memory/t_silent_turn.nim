## Tests for core/memory/silent_turn.nim

import std/[json, strutils, options]
import std/unittest

import donkey/core/memory/silent_turn
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message

suite "silent_turn":
  
  suite "formatConversationForMemory":
    
    test "empty history returns empty string":
      let history = newHistory()
      let result = formatConversationForMemory(history)
      check result == ""
    
    test "single user message":
      var history = newHistory()
      history.addUser("Hello, my name is John")
      let result = formatConversationForMemory(history)
      check result == "user: Hello, my name is John"
    
    test "multiple messages":
      var history = newHistory()
      history.addUser("I prefer Rust over Python")
      history.addAssistant("Noted! Rust is a great choice for systems programming.")
      history.addUser("Yes, and I work on embedded systems")
      let result = formatConversationForMemory(history)
      check result.contains("user: I prefer Rust over Python")
      check result.contains("assistant: Noted!")
      check result.contains("user: Yes, and I work on embedded systems")
    
    test "truncates very long messages":
      var history = newHistory()
      let longText = "x".repeat(3000)
      history.addUser(longText)
      let result = formatConversationForMemory(history)
      check result.len < longText.len
      check result.endsWith("...")

    test "bounds very long histories":
      var history = newHistory()
      for i in 0 ..< 100:
        history.addUser("message " & $i)
      let result = formatConversationForMemory(history)
      check result.len <= 12_000
      check result.contains("message 99")

    test "preserves short messages":
      var history = newHistory()
      history.addUser("Hi")
      history.addAssistant("Hello!")
      let result = formatConversationForMemory(history)
      check result == "user: Hi\nassistant: Hello!"
  
  suite "parseMemoryExtractionResponse":
    
    test "empty response returns empty result":
      let result = parseMemoryExtractionResponse("")
      check result.isOk
      let okResult = result.get()
      check okResult.triplesCount == 0
      check okResult.factsCount == 0
      check okResult.preferencesCount == 0
      check okResult.conceptsCount == 0
    
    test "parses valid JSON with triples":
      let response = """{
        "triples": [
          {"subject": "John", "predicate": "prefers", "object": "Rust", "confidence": 0.9},
          {"subject": "John", "predicate": "works on", "object": "embedded systems", "confidence": 0.8}
        ],
        "facts": [],
        "preferences": [],
        "concepts": []
      }"""
      let result = parseMemoryExtractionResponse(response)
      check result.isOk
      let okResult = result.get()
      check okResult.triplesCount == 2
      check okResult.factsCount == 0
      check okResult.preferencesCount == 0
      check okResult.conceptsCount == 0
    
    test "parses JSON with facts":
      let response = """{
        "triples": [],
        "facts": ["User works at Acme Corp", "Project deadline is March 2026"],
        "preferences": [],
        "concepts": []
      }"""
      let result = parseMemoryExtractionResponse(response)
      check result.isOk
      let okResult = result.get()
      check okResult.triplesCount == 0
      check okResult.factsCount == 2
      check okResult.preferencesCount == 0
      check okResult.conceptsCount == 0
    
    test "parses JSON with preferences":
      let response = """{
        "triples": [],
        "facts": [],
        "preferences": ["prefers Portuguese", "likes detailed explanations"],
        "concepts": []
      }"""
      let result = parseMemoryExtractionResponse(response)
      check result.isOk
      let okResult = result.get()
      check okResult.preferencesCount == 2
    
    test "parses JSON with concepts":
      let response = """{
        "triples": [],
        "facts": [],
        "preferences": [],
        "concepts": ["Nim programming", "hexagonal architecture"]
      }"""
      let result = parseMemoryExtractionResponse(response)
      check result.isOk
      let okResult = result.get()
      check okResult.conceptsCount == 2
    
    test "parses complete response":
      let response = """{
        "triples": [
          {"subject": "Donkey", "predicate": "is", "object": "AI agent system", "confidence": 0.95}
        ],
        "facts": ["Built with Nim language", "Uses Chronos for async"],
        "preferences": ["prefers Zhipu provider"],
        "concepts": ["hexagonal architecture", "pipeops pattern"]
      }"""
      let result = parseMemoryExtractionResponse(response)
      check result.isOk
      let okResult = result.get()
      check okResult.triplesCount == 1
      check okResult.factsCount == 2
      check okResult.preferencesCount == 1
      check okResult.conceptsCount == 2
    
    test "invalid JSON returns error":
      let response = "not valid json {"
      let result = parseMemoryExtractionResponse(response)
      check result.isErr
      check result.error.contains("parse")
    
    test "missing fields use defaults":
      let response = """{"triples": [{"subject": "A", "predicate": "B", "object": "C"}]}"""
      let result = parseMemoryExtractionResponse(response)
      check result.isOk
      let okResult = result.get()
      check okResult.triplesCount == 1
      check okResult.factsCount == 0
      check okResult.preferencesCount == 0
      check okResult.conceptsCount == 0
  
  suite "tryParseJson":
    
    test "valid JSON returns some":
      let result = tryParseJson("""{"key": "value"}""")
      check result.isSome
      check result.get()["key"].getStr() == "value"
    
    test "invalid JSON returns none":
      let result = tryParseJson("not json")
      check result.isNone
    
    test "empty string returns none":
      let result = tryParseJson("")
      check result.isNone
