## WebFetchTools — ToolPort adapter for web content fetching.
##
## Tools:
##   - web_fetch — fetch URL and return HTML content as clean text/Markdown

import std/[json]
import ../../ports/tool
import ../../core/pipeops
import ../../domain/tools/web_fetch_helpers
import ../../adapters/http/std_http

type
  WebFetchTools* = object
    http*: StdHttpAdapter
    workspace*: string  # optional workspace restriction

# Tool schema
proc webFetchSchema*(): ToolSchema =
  ToolSchema(
    name: "web_fetch",
    description: "Fetch the text content of a public URL and convert to clean text.",
    inputSchema: %* {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "description": "Public URL to fetch"
        },
        "max_chars": {
          "type": "integer",
          "description": "Maximum characters to return (default: 5000)"
        }
      },
      "required": ["url"]
    }
  )

# listTools
proc listTools*(wf: WebFetchTools): Result[seq[ToolSchema], string] =
  ok(@[webFetchSchema()])

# invoke
proc invoke*(wf: var WebFetchTools; call: ToolCall): Result[ToolResult, string] =
  case call.name
  of "web_fetch":
    let urlNode = call.input.getOrDefault("url")
    if urlNode.isNil or urlNode.kind != JString or urlNode.getStr("").len == 0:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"missing required field: url\"}", isError: true))
    
    let rawUrl = urlNode.getStr("")
    let maxCharsNode = call.input.getOrDefault("max_chars")
    let maxChars = if maxCharsNode.isNil or maxCharsNode.kind != JInt: 5000 else: maxCharsNode.getInt()
    
    # SSRF check
    if rawUrl.isPrivateUrl:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"private/internal addresses not allowed\"}", isError: true))
    
    # Fetch via HTTP
    let resp = wf.http.get(rawUrl)
    if resp.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & resp.error & "\"}", isError: true))
    
    let r = resp.get()
    if r.status < 200 or r.status >= 300:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"HTTP error " & $r.status & "\"}", isError: true))
    
    let text = htmlToText(r.body, maxChars)
    return ok(ToolResult(callId: call.id, output: text, isError: false))
  
  else:
    return ok(ToolResult(callId: call.id, output: "{\"error\": \"unknown tool\"}", isError: true))

# Constructor
proc newWebFetchTools*(http: StdHttpAdapter = newStdHttpAdapter(); workspace: string = ""): WebFetchTools =
  WebFetchTools(http: http, workspace: workspace)
