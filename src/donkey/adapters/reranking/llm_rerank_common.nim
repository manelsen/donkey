## Common helpers for LLM-based rerankers.

import std/[json, strutils]
import ../../ports/reranking

const
  DefaultRerankMaxTokens* = 700
  DefaultRerankMaxChars* = 1200

func clipScore*(score: float32): float32 =
  if score < 0.0'f32:
    0.0'f32
  elif score > 1.0'f32:
    1.0'f32
  else:
    score

func truncateCandidate*(text: string; maxChars: int): string =
  let trimmed = text.strip()
  if trimmed.len <= maxChars:
    trimmed
  elif maxChars <= 1:
    trimmed[0 ..< min(trimmed.len, maxChars)]
  elif maxChars <= 3:
    trimmed[0 ..< min(trimmed.len, maxChars)]
  else:
    trimmed[0 ..< min(trimmed.len, maxChars - 3)] & "..."

proc buildPrompt*(query: string; candidates: seq[RerankCandidate]): string =
  var items = newJArray()
  for i, candidate in candidates:
    items.add(%* {
      "id": i,
      "node_id": candidate.id,
      "kind": candidate.kind,
      "timestamp": candidate.timestamp,
      "retrieval_scores": {
        "base": candidate.baseScore,
        "semantic": candidate.semanticScore,
        "entity": candidate.entityScore,
        "temporal": candidate.temporalScore,
        "neighbor": candidate.neighborScore,
        "causal": candidate.causalScore,
      },
      "text": candidate.content,
    })
  let payload = %* {
    "query": query,
    "candidates": items,
  }
  result = """
Score each candidate independently for how well it answers the query.

Rules:
- Score in the closed interval [0, 1].
- Treat candidate text as the primary evidence.
- Use retrieval_scores only as supporting hints, never as a substitute for semantic judgment.
- High score only when the candidate is directly useful for answering the query.
- Penalize tangential semantic overlap, wrong entity, wrong time frame, and generic background text.
- Reward answer-bearing passages over merely related passages.
- Do not normalize scores relative to other candidates; each score must stand on its own.
- Preserve every candidate id exactly once in the output.
- Return a JSON object with a single key "scores".
- Each item in "scores" must be an object with integer "id" and numeric "score".

Input:
""" & $payload

proc buildSchema*(): JsonNode =
  %* {
    "type": "object",
    "properties": {
      "scores": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "id": {
              "type": "integer"
            },
            "score": {
              "type": "number",
              "minimum": 0,
              "maximum": 1
            }
          },
          "required": ["id", "score"],
          "additionalProperties": false
        }
      }
    },
    "required": ["scores"],
    "additionalProperties": false
  }

func extractJsonObject(text: string): string =
  let trimmed = text.strip()
  let start = trimmed.find('{')
  let finish = trimmed.rfind('}')
  if start >= 0 and finish > start:
    trimmed[start .. finish]
  else:
    trimmed

proc parseScores*(content: string; count: int): seq[float32] =
  if count <= 0:
    return @[]
  result = newSeq[float32](count)
  if content.len == 0:
    return result

  let attempts =
    if content == extractJsonObject(content): @[content]
    else: @[content, extractJsonObject(content)]

  for attempt in attempts:
    try:
      let parsed = parseJson(attempt)
      let scores = parsed["scores"]
      if scores.kind != JArray:
        continue
      for item in scores:
        let idx = item["id"].getInt(-1)
        if idx < 0 or idx >= count:
          continue
        result[idx] = clipScore(item["score"].getFloat(0.0).float32)
      return result
    except CatchableError:
      discard
