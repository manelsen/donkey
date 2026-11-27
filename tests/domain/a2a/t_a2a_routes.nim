## E13.4: the A2A routes on the gateway, and who authenticates them.

import std/unittest
import donkey/domain/gateway/auth_pure
import donkey/domain/gateway/routing_pure

proc runTests*() =
  suite "a2a — routes":
    test "the card, the JSON-RPC endpoint and the pairing":
      check routeGatewayRequest(GatewayRequest(meth: "GET", path: "/.well-known/agent-card.json")) == "a2a_card"
      check routeGatewayRequest(GatewayRequest(meth: "POST", path: "/a2a")) == "a2a_rpc"
      check routeGatewayRequest(GatewayRequest(meth: "POST", path: "/a2a/pair")) == "a2a_pair"
      check routeGatewayRequest(GatewayRequest(meth: "POST", path: "/a2a/pair/poll")) == "a2a_pair_poll"

    test "the card is public; the rest is the paired agent's own credential, never the operator's token":
      check gatewayAuthVerdict("a2a_card", "", "op-token") == gavPublic
      for action in ["a2a_rpc", "a2a_pair", "a2a_pair_poll"]:
        check isEditorAction(action)
        check gatewayAuthVerdict(action, "", "op-token") == gavEditor

when isMainModule:
  runTests()
