## Pure parsing helpers for memory reranker preferences.

import std/strutils

const
  MemoryRerankOff* = "off"
  MemoryRerankExplicit* = "explicit"
  MemoryRerankDialogue* = "dialogue"

type
  MemoryRerankPrefs* = object
    mode*: string
    provider*: string
    model*: string

func defaultMemoryRerankPrefs*(): MemoryRerankPrefs =
  MemoryRerankPrefs(mode: "", provider: "", model: "")

func normalizeMemoryRerankMode*(value: string): string =
  let normalized = value.strip.toLowerAscii()
  case normalized
  of "", "default":
    ""
  of "off", "none", "disabled":
    MemoryRerankOff
  of "explicit", "fixed", "pinned":
    MemoryRerankExplicit
  of "dialogue", "chat", "follow-chat", "follow-dialogue", "follow-model":
    MemoryRerankDialogue
  else:
    ""

func parseMemoryRerankPrefs*(preferencesMd: string): MemoryRerankPrefs =
  result = defaultMemoryRerankPrefs()
  for line in preferencesMd.splitLines():
    let parts = line.split('=', 1)
    if parts.len != 2:
      continue
    let key = parts[0].strip()
    let value = parts[1].strip().strip(chars = {'"'})
    case key
    of "memory_rerank", "memory_rerank_mode":
      result.mode = normalizeMemoryRerankMode(value)
    of "memory_rerank_provider":
      result.provider = value
    of "memory_rerank_model":
      result.model = value
    else:
      discard
