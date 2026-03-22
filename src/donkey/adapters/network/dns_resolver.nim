## dns_resolver.nim — DNS resolution adapter with SSRF protection.
##
## Wraps nativesockets.getAddrInfo in a Result[string, string] API and delegates
## private-IP checking to core/dns.blockIfPrivate.
## Exceptions from getAddrInfo/getAddrString are caught here — never leak to callers.
##
## Usage:
##   let r = safeResolve("example.com")   # Ok("1.2.3.4") or Err("SSRF blocked…")
##   let r = "api.example.com" |> safeResolve
##   let r = safeResolve(host) >>= openConnection

import std/nativesockets
import ../../core/pipeops
import ../../core/dns

proc safeResolve*(host: string): Result[string, string] {.raises: [].} =
  ## Resolves `host` to an IP address via the system DNS resolver.
  ## Returns Err if:
  ##   - the domain cannot be resolved (DNS failure)
  ##   - any resolved IP is private, loopback, or reserved (SSRF protection)
  ## Returns Ok(firstPublicIp) when all resolved addresses are public.
  try:
    var info = getAddrInfo(host, Port(0), AF_UNSPEC, SOCK_STREAM)
    defer: freeAddrInfo(info)
    var firstPublicIp = ""
    var it = info
    while it != nil:
      let ipStr = getAddrString(it.ai_addr)
      let check = ipStr |> blockIfPrivate
      if check.isErr:
        return check
      if firstPublicIp.len == 0:
        firstPublicIp = ipStr
      it = it.ai_next
    if firstPublicIp.len == 0:
      err("no addresses resolved for '" & host & "'")
    else:
      ok(firstPublicIp)
  except CatchableError as e:
    err("DNS resolution failed for '" & host & "': " & e.msg)
