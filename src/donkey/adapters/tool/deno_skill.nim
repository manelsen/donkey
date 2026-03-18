## DenoSkillAdapter — specialisation of McpClientAdapter for Deno/Clawhub skills.
##
## Skills are TypeScript/JavaScript packages that expose MCP-compatible tools.
## They run as Deno subprocesses with an explicit permission allowlist.
##
## Usage:
##   let skill = newDenoSkillAdapter("/path/to/skill.ts",
##                                   @["--allow-net", "--allow-read=/tmp"])
##   let tools  = skill.listTools()
##   let result = skill.invoke(ToolCall(...))

import ./mcp_client

export mcp_client

proc newDenoSkillAdapter*(scriptPath: string;
                           permissions: seq[string]): McpClientAdapter =
  ## Creates an McpClientAdapter that spawns `deno run <permissions> <script>`.
  let args = @["run"] & permissions & @[scriptPath]
  newMcpClient("deno", args)
