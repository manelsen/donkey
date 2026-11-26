## deno_skill — a Deno skill (Clawhub or custom) as an MCP server in a
## sandboxed subprocess: `deno run <permissions> <script>`, driven by the
## asynchronous stdio client (mcp_client) like any MCP server.
##
## Threat model: Deno's --allow-* flags enforce OS-level boundaries. See
## CLAUDE.md "Threat model — Skills de terceiros" for the full analysis.

import ./mcp_client
export mcp_client

proc newDenoSkillAdapter*(script: string;
                          permissions: seq[string] = @[]): McpClient =
  newMcpClient("deno", @["run"] & permissions & @[script])
