## ToolsRegistry — load/save MCP server and Deno skill registrations.
##
## Registry file: {donkeyHome}/tools.toml
##
## Format:
##   [[tool]]
##   kind    = "mcp"          # "mcp" | "deno"
##   command = "my-mcp-server"
##   args    = ["--port", "8080"]
##   permissions = []         # Deno only: ["--allow-net", ...]
##
##   [[tool]]
##   kind    = "deno"
##   command = "/skills/search.ts"
##   permissions = ["--allow-net"]

import std/os
import parsetoml
import ../adapters/tool/mcp_client
import ../adapters/tool/deno_skill

type
  ToolKind* = enum
    tkMcp, tkDeno

  ToolEntry* = object
    kind*:        ToolKind
    command*:     string
    args*:        seq[string]
    permissions*: seq[string]  ## Deno only

proc loadToolRegistry*(path: string): seq[ToolEntry] =
  ## Reads tools.toml. Returns empty seq if file absent or malformed.
  if not fileExists(path):
    return @[]
  try:
    let t = parsetoml.parseFile(path)
    let tools = t.getOrDefault("tool")
    if tools == nil or tools.kind != TomlValueKind.Array:
      return @[]
    for item in tools.arrayVal:
      let kind = item.getOrDefault("kind").getStr("mcp")
      var entry = ToolEntry(
        kind:    if kind == "deno": tkDeno else: tkMcp,
        command: item.getOrDefault("command").getStr(""),
      )
      let argsNode = item.getOrDefault("args")
      if argsNode != nil and argsNode.kind == TomlValueKind.Array:
        for a in argsNode.arrayVal:
          entry.args.add(a.getStr(""))
      let permNode = item.getOrDefault("permissions")
      if permNode != nil and permNode.kind == TomlValueKind.Array:
        for p in permNode.arrayVal:
          entry.permissions.add(p.getStr(""))
      if entry.command.len > 0:
        result.add(entry)
  except: discard

proc saveToolEntry*(path: string; entry: ToolEntry) =
  ## Appends one [[tool]] section to the registry file.
  createDir(path.parentDir())
  var toml = "\n[[tool]]\n"
  toml.add("kind    = \"" & (if entry.kind == tkDeno: "deno" else: "mcp") & "\"\n")
  toml.add("command = \"" & entry.command & "\"\n")
  if entry.args.len > 0:
    toml.add("args    = [")
    for i, a in entry.args:
      if i > 0: toml.add(", ")
      toml.add("\"" & a & "\"")
    toml.add("]\n")
  if entry.permissions.len > 0:
    toml.add("permissions = [")
    for i, p in entry.permissions:
      if i > 0: toml.add(", ")
      toml.add("\"" & p & "\"")
    toml.add("]\n")
  let existing = if fileExists(path): readFile(path) else: ""
  writeFile(path, existing & toml)

proc buildMcpClient*(entry: ToolEntry): McpClientAdapter =
  ## Creates the right adapter from a ToolEntry.
  case entry.kind
  of tkDeno:
    newDenoSkillAdapter(entry.command, entry.permissions)
  of tkMcp:
    newMcpClient(entry.command, entry.args)
