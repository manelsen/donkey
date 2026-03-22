## tools_registry — persist and load MCP server entries in tools.toml.
##
## File format (TOML, one [[tool]] section per entry):
##   [[tool]]
##   kind    = "mcp"
##   command = "uvx"
##   args    = ["mcp-server-fetch"]

import std/[os]
import parsetoml
import ../adapters/tool/mcp_client

type
  ToolKind* = enum
    tkMcp

  ToolEntry* = object
    kind*:    ToolKind
    command*: string
    args*:    seq[string]

proc saveToolEntry*(path: string; entry: ToolEntry) =
  ## Appends one [[tool]] section to the TOML file at `path`.
  ## Creates the file (and parent dirs) if it does not exist.
  createDir(parentDir(path))
  var f = open(path, fmAppend)
  defer: f.close()
  f.writeLine("\n[[tool]]")
  f.writeLine("kind    = \"mcp\"")
  f.writeLine("command = \"" & entry.command & "\"")
  var argsLit = "["
  for i, a in entry.args:
    if i > 0: argsLit.add(", ")
    argsLit.add("\"" & a & "\"")
  argsLit.add("]")
  f.writeLine("args    = " & argsLit)

proc loadToolRegistry*(path: string): seq[ToolEntry] =
  ## Reads all [[tool]] entries from the TOML file at `path`.
  ## Returns empty seq if file does not exist or contains no entries.
  if not fileExists(path):
    return @[]
  let t = parsetoml.parseFile(path)
  if not t.hasKey("tool"):
    return @[]
  for node in t["tool"].getElems():
    let kind = node.getOrDefault("kind").getStr("mcp")
    let cmd  = node.getOrDefault("command").getStr("")
    var args: seq[string]
    if node.hasKey("args"):
      for a in node["args"].getElems():
        args.add(a.getStr(""))
    if cmd.len > 0:
      result.add(ToolEntry(kind: tkMcp, command: cmd, args: args))

proc buildMcpClient*(entry: ToolEntry): McpClientAdapter =
  ## Constructs an McpClientAdapter from a registry entry.
  newMcpClient(entry.command, entry.args)
