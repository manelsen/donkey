## profile_azure.nim — Azure OpenAI's compat profile.
##
## Microsoft's v1 GA API (learn.microsoft.com, "Azure OpenAI API version
## lifecycle"; REST reference "Chat completions", v1): POST
## {resource}/openai/v1/chat/completions, `api-version` no longer required,
## the key in the `api-key` header, `model` holding the deployment name. The
## wire is the OpenAI dialect (tools, tool_calls, SSE ending in [DONE]); Azure
## adds `reasoning_content`, which the parsers already read.
##
## Pure data and URL logic, no I/O.

import std/strutils
import ../../core/pipeops
import ./compat
import ./openai_pure

func endpointSafe(url: string): bool =
  ## The key travels with every request: https, or plain http only to this
  ## machine; never userinfo in the authority.
  let lower = url.toLowerAscii
  let schemeEnd = lower.find("://")
  if schemeEnd <= 0: return false
  var authority = lower[schemeEnd + 3 .. ^1]
  for stop in ['/', '?', '#']:
    let at = authority.find(stop)
    if at >= 0: authority = authority[0 ..< at]
  if '@' in authority or authority.len == 0: return false
  let host = authority.split(':')[0]
  lower.startsWith("https://") or
    (lower.startsWith("http://") and host in ["localhost", "127.0.0.1", "[::1]"])

func azureChatEndpoint*(resourceUrl: string): Result[string, string] =
  ## The chat endpoint from AZURE_OPENAI_ENDPOINT: the resource root
  ## (https://<name>.openai.azure.com or .services.ai.azure.com), its
  ## /openai/v1 base, or the full endpoint.
  var value = resourceUrl.strip
  while value.endsWith("/"):
    value.setLen(value.len - 1)
  if value.len == 0:
    return err("Azure OpenAI: set AZURE_OPENAI_ENDPOINT to the resource URL " &
               "(https://<name>.openai.azure.com)")
  if not endpointSafe(value):
    return err("Azure OpenAI: AZURE_OPENAI_ENDPOINT must be https (" & value & ")")
  if value.endsWith("/chat/completions"):
    ok(value)
  elif value.endsWith("/openai/v1"):
    ok(value & "/chat/completions")
  else:
    ok(value & "/openai/v1/chat/completions")

func azureCompatProfileAt*(endpoint: string): CompatProfile =
  result = CompatProfile(
    id: "azure",
    endpoint: endpoint,
    supportsImages: true,   ## per-model decision: media_pure.visionSupport
    quirks: defaultOpenAiQuirks(),
    apiKeyHeader: "api-key",
  )
  result.quirks.includeReasoningField = false
