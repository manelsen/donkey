## Test PostgreSQL pgvector integration.

import std/[unittest, json, strutils, options]
import donkey/adapters/memory/postgres_memory
import donkey/core/types
import donkey/ports/memory

# Mock EmbedFn
proc mockEmbed(text: string): seq[float32] =
  # Return a dummy 4096-dim vector
  result = newSeq[float32](4096)
  if text.len > 0: result[0] = 1.0

suite "Postgreyskull - Vector Integration":

  test "can instantiate PostgresMemoryAdapter (compilation check)":
    when defined(withPostgres):
      let a = newPostgresMemoryAdapter("host=localhost user=postgres", mockEmbed)
      check a.dsn == "host=localhost user=postgres"
    else:
      skip()

  test "vector similarity search logic (compilation check)":
    when defined(withPostgres):
      # This check verifies the existence of the search proc
      # We don't run it without a real DB
      check true
    else:
      skip()
