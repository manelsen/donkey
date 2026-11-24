## BacktrailPort — what kind of message arrived, before the model's turn.
##
## A decision model reads the incoming message and gives its route
## (`domain/memory/backtrail_pure`). The adapter
## (`adapters/decision/perplexity_backtrail`) builds it from a key; with no
## key the field stays nil and Backtrail is off.

import ../core/pipeops
import ../domain/memory/backtrail_pure

export backtrail_pure

type
  BacktrailPort* = object
    classify*: proc(message: string): Result[RouteDecision, string] {.gcsafe, raises: [].}

func backtrailAvailable*(port: BacktrailPort): bool =
  port.classify != nil
