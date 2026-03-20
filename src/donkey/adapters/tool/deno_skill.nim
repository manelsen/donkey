## DenoSkillAdapter — ToolPort wrapper for Deno-based skills (Clawhub/custom).
##
## Skills are TypeScript/JS files executed via `deno run` with explicit
## --allow-* permission flags. Communicates via MCP JSON-RPC over stdin/stdout,
## identical to McpClientAdapter — Deno skills are just MCP servers in a Deno
## subprocess.
##
## Threat model: Deno sandbox enforces OS-level boundaries. See CLAUDE.md
## "Threat model — Skills de terceiros" for the full analysis.

import ./mcp_client

type
  DenoSkillAdapter* = McpClientAdapter

proc newDenoSkillAdapter*(script: string;
                           permissions: seq[string] = @[]): DenoSkillAdapter =
  ## Builds an McpClientAdapter that runs `deno run <permissions> <script>`.
  let args = permissions & @[script]
  newMcpClient("deno", @["run"] & args)
