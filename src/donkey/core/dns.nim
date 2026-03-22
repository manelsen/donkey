## dns.nim — pure SSRF-guard helpers for DNS validation.
##
## Builds on network.nim (isPrivateIp) with pipeline-friendly combinators.
## No I/O — resolvers live in adapters/network/dns_resolver.nim.
##
## Usage:
##   "192.168.1.1" |> blockIfPrivate      # Err("SSRF blocked: …")
##   "8.8.8.8"     |> blockIfPrivate      # Ok("8.8.8.8")
##
##   # Last-arg form for labelled contexts:
##   "10.0.0.1" |>-> labelledBlock("outbound")   # Err("outbound: …")
##
##   # Railway chaining:
##   resolvedIp |> blockIfPrivate >>= persistConnection

import ./pipeops
import ./network

func blockIfPrivate*(ip: string): Result[string, string] {.raises: [].} =
  ## Returns ok(ip) for public addresses, err(…) for private/reserved ones.
  ## Designed as a unary combinator for |> pipelines and >>= chaining.
  ## Wraps isPrivateIp's ValueError in a Result so callers stay exception-free.
  try:
    let isPriv = ? isPrivateIp(ip)
    if isPriv:
      err("SSRF blocked: " & ip & " is a private address")
    else:
      ok(ip)
  except ValueError as e:
    err("invalid IP format: " & e.msg)

func labelledBlock*(label: string; ip: string): Result[string, string] {.raises: [].} =
  ## Like blockIfPrivate but prefixes `label` to any error message.
  ## Last-arg position enables |>-> syntax: ip |>-> labelledBlock("ctx").
  try:
    let isPriv = ? isPrivateIp(ip)
    if isPriv:
      err(label & ": " & ip & " is a private address")
    else:
      ok(ip)
  except ValueError as e:
    err(label & ": invalid IP format: " & e.msg)
