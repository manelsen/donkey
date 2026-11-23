## tools_registry — persist and load MCP server entries in tools.toml.
##
## File format (TOML, one [[tool]] section per entry):
##   [[tool]]
##   kind    = "mcp"                 # a local server over stdio
##   command = "uvx"
##   args    = ["mcp-server-fetch"]
##
##   [[tool]]
##   kind      = "mcp-http"          # a remote server over Streamable HTTP
##   url       = "https://mcp.example.com/mcp"
##   token_env = "EXAMPLE_MCP_TOKEN" # optional: the env var holding a bearer
##
## The token itself never goes in this file; only the name of the variable.

import std/[os, strutils, uri]
import ../adapters/tool/mcp_client
import ../core/pipeops
import ./toml

type
  ToolKind* = enum
    tkMcp       ## stdio subprocess
    tkMcpHttp   ## Streamable HTTP endpoint

  ToolEntry* = object
    kind*:     ToolKind
    command*:  string
    args*:     seq[string]
    url*:      string
    tokenEnv*: string

func tomlString(value: string): string =
  "\"" & value.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

func validMcpHttpUrl*(url: string): Result[void, string] =
  ## https only, except on this machine: a bearer must not travel in clear.
  let parsed = parseUri(url)
  if parsed.hostname.len == 0:
    return err("not a URL: " & url)
  case parsed.scheme
  of "https": ok()
  of "http":
    if parsed.hostname in ["localhost", "127.0.0.1", "::1"]: ok()
    else: err("an MCP server off this machine must use https: " & url)
  else:
    err("an MCP server URL must be https: " & url)

proc saveToolEntry*(path: string; entry: ToolEntry) =
  ## Appends one [[tool]] section to the TOML file at `path`.
  ## Creates the file (and parent dirs) if it does not exist.
  createDir(parentDir(path))
  var f = open(path, fmAppend)
  defer: f.close()
  f.writeLine("\n[[tool]]")
  case entry.kind
  of tkMcp:
    f.writeLine("kind    = \"mcp\"")
    f.writeLine("command = " & tomlString(entry.command))
    var argsLit = "["
    for i, a in entry.args:
      if i > 0: argsLit.add(", ")
      argsLit.add(tomlString(a))
    argsLit.add("]")
    f.writeLine("args    = " & argsLit)
  of tkMcpHttp:
    f.writeLine("kind      = \"mcp-http\"")
    f.writeLine("url       = " & tomlString(entry.url))
    if entry.tokenEnv.len > 0:
      f.writeLine("token_env = " & tomlString(entry.tokenEnv))

proc loadToolRegistry*(path: string): seq[ToolEntry] {.gcsafe.} =
  ## Reads all [[tool]] entries from the TOML file at `path`.
  ## Returns empty seq if file does not exist or contains no entries.
  if not fileExists(path):
    return @[]
  var t: TomlValueRef
  t = parseTomlFile(path)
  if not t.hasKey("tool"):
    return @[]
  for node in t["tool"].getElems():
    let kind = node.getOrDefault("kind").getStr("mcp")
    if kind == "mcp-http":
      let url = node.getOrDefault("url").getStr("")
      if url.len > 0:
        result.add(ToolEntry(kind: tkMcpHttp, url: url,
                             tokenEnv: node.getOrDefault("token_env").getStr("")))
      continue
    let cmd  = node.getOrDefault("command").getStr("")
    var args: seq[string]
    if node.hasKey("args"):
      for a in node["args"].getElems():
        args.add(a.getStr(""))
    if cmd.len > 0:
      result.add(ToolEntry(kind: tkMcp, command: cmd, args: args))

proc buildMcpClient*(entry: ToolEntry): McpClientAdapter =
  ## Constructs an McpClientAdapter from a stdio registry entry.
  newMcpClient(entry.command, entry.args)
