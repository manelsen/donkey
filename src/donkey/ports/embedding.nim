## EmbeddingPort — concept for text embedding adapters.
##
## Returns a dense float32 vector suitable for pgvector storage.
## Dimension depends on the model (qwen3-embedding: 4096).

import ../core/pipeops

type
  EmbedFn* = proc(text: string): seq[float32]
  ## Closure form — same pattern as CompleteFn. Embeddings never fail
  ## in the interface (caller receives empty slice on error).

  EmbeddingPort* = concept e
    e.embed(string) is seq[float32]
