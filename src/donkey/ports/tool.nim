## ToolPort — concept for MCP-compatible tool providers.
##
## Covers both MCP servers and Deno/Clawhub skills — all treated identically
## as JSON-RPC processes. One ToolPort, one McpClientAdapter.
##
## Adapters: McpClientAdapter (subprocess JSON-RPC via stdin/stdout).

import std/json
import ../core/pipeops

type
  ToolSchema* = object
    ## Describes a single callable tool (matches MCP tools/list format).
    name*:        string
    description*: string
    inputSchema*: JsonNode   ## JSON Schema object (type, properties, required)

  ToolCall* = object
    ## A request to invoke one tool.
    id*:    string   ## caller-assigned correlation id
    name*:  string   ## tool name as returned by listTools
    input*: JsonNode ## arguments matching inputSchema

  ToolResult* = object
    ## Result of a tool invocation.
    callId*:  string
    output*:  string
    isError*: bool

  ToolPort* = concept t
    t.listTools() is Result[seq[ToolSchema], string]
    ## Returns all tools exposed by this endpoint.

    t.invoke(ToolCall) is Result[ToolResult, string]
    ## Invokes one tool. Returns result or error description.

  ToolRuntimePort* = object
    listTools*: proc(): Result[seq[ToolSchema], string] {.gcsafe.}
    invoke*:    proc(call: ToolCall): Result[ToolResult, string] {.gcsafe.}
    close*:     proc() {.gcsafe.}

  LoadedToolRuntime* = object
    port*:    ToolRuntimePort
    schemas*: seq[ToolSchema]

  SkillRuntimeBuilder* = proc(script: string; permissions: seq[string]): Result[LoadedToolRuntime, string]
                           {.gcsafe.}
