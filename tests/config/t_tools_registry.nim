## tools.toml: stdio and Streamable HTTP MCP servers.

import std/[os, strutils, unittest]
import donkey/core/pipeops
import donkey/config/tools_registry

const Tmp = "/tmp/donkey_t_tools_registry"

proc fresh(name: string): string =
  createDir(Tmp)
  result = Tmp / name
  removeFile(result)

proc runTests*() =
  suite "tools registry":
    test "a stdio server round-trips":
      let path = fresh("stdio.toml")
      saveToolEntry(path, ToolEntry(kind: tkMcp, command: "uvx", args: @["mcp-server-fetch"]))
      let entries = loadToolRegistry(path)
      check entries.len == 1
      check entries[0].kind == tkMcp
      check entries[0].command == "uvx"
      check entries[0].args == @["mcp-server-fetch"]

    test "an HTTP server round-trips with its token env name, never the token":
      let path = fresh("http.toml")
      saveToolEntry(path, ToolEntry(kind: tkMcpHttp, url: "https://mcp.example.test/mcp",
                                    tokenEnv: "EXAMPLE_MCP_TOKEN"))
      let text = readFile(path)
      check "mcp-http" in text
      let entries = loadToolRegistry(path)
      check entries.len == 1
      check entries[0].kind == tkMcpHttp
      check entries[0].url == "https://mcp.example.test/mcp"
      check entries[0].tokenEnv == "EXAMPLE_MCP_TOKEN"

    test "both kinds side by side, and quotes in values survive":
      let path = fresh("mixed.toml")
      saveToolEntry(path, ToolEntry(kind: tkMcp, command: "run", args: @["a \"b\"", "c\\d"]))
      saveToolEntry(path, ToolEntry(kind: tkMcpHttp, url: "https://h.test/mcp"))
      let entries = loadToolRegistry(path)
      check entries.len == 2
      check entries[0].args == @["a \"b\"", "c\\d"]
      check entries[1].kind == tkMcpHttp and entries[1].tokenEnv == ""

    test "an OAuth server round-trips its auth mode":
      let path = fresh("oauth.toml")
      saveToolEntry(path, ToolEntry(kind: tkMcpHttp, url: "https://h.test/mcp", oauth: true))
      let entries = loadToolRegistry(path)
      check entries[0].oauth and entries[0].tokenEnv == ""

    test "an HTTP server must use https, except on the local machine":
      check validMcpHttpUrl("https://mcp.example.test/mcp").isOk
      check validMcpHttpUrl("http://127.0.0.1:8080/mcp").isOk
      check validMcpHttpUrl("http://localhost:8080/mcp").isOk
      check validMcpHttpUrl("http://mcp.example.test/mcp").isErr
      check validMcpHttpUrl("ftp://x").isErr
      check validMcpHttpUrl("").isErr

when isMainModule:
  runTests()
