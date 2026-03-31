## Test network boundary and allowlist.

import std/[unittest, json]
import donkey/core/pipeops
import donkey/core/security/net_boundary

suite "Network Boundary - Deny by Default":

  test "blocks host not in allowlist":
    let allowlist = @["api.openai.com", "api.anthropic.com"]
    check isHostAllowed("malicious.com", allowlist) == false

  test "allows host in allowlist (exact)":
    let allowlist = @["api.openai.com", "api.anthropic.com"]
    check isHostAllowed("api.openai.com", allowlist) == true

  test "allows subdomain if parent in allowlist":
    let allowlist = @["openai.com"]
    check isHostAllowed("api.openai.com", allowlist) == true
    check isHostAllowed("v1.api.openai.com", allowlist) == true

  test "empty allowlist blocks everything":
    let allowlist: seq[string] = @[]
    check isHostAllowed("any.com", allowlist) == false
