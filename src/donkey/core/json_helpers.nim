## json_helpers — null-safe JSON field access templates.
## Reduces the `if node != nil: node.getOrDefault(key).getInt(0) else: 0` boilerplate
## that appears throughout adapter response parsers.

import std/json

template jInt*(node: JsonNode; key: string; default = 0): int =
  ## Returns node[key].getInt(default) if node is non-nil and has key, else default.
  (block:
    let n = node
    if n != nil and n.hasKey(key): n[key].getInt(default) else: default)

template jStr*(node: JsonNode; key: string; default = ""): string =
  ## Returns node[key].getStr(default) if node is non-nil and has key, else default.
  (block:
    let n = node
    if n != nil and n.hasKey(key): n[key].getStr(default) else: default)
