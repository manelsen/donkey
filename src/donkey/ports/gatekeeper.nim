## GatekeeperPort — what kind of message arrived, before the model's turn.
##
## A decision model reads the incoming message and gives its route
## (`domain/memory/gatekeeper_pure`). The adapter
## (`adapters/decision/perplexity_gatekeeper`) builds it from a key; with no
## key the field stays nil and there is no gatekeeper.

import ../core/pipeops
import ../domain/memory/gatekeeper_pure

export gatekeeper_pure

type
  GatekeeperPort* = object
    classify*: proc(message: string): Result[RouteDecision, string] {.gcsafe, raises: [].}

func gatekeeperAvailable*(port: GatekeeperPort): bool =
  port.classify != nil
