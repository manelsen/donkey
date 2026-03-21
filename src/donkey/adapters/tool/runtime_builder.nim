## Concrete tool runtime builders for local skill processes.

import ../../core/pipeops
import ../../ports/tool
import deno_skill

proc buildDenoSkillRuntime*(script: string;
                            permissions: seq[string]): Result[LoadedToolRuntime, string] {.gcsafe.} =
  var client = newDenoSkillAdapter(script, permissions)
  let schemasRes = client.listTools()
  if schemasRes.isErr:
    return err(schemasRes.error)
  ok(LoadedToolRuntime(
    port: client.toRuntimePort(),
    schemas: schemasRes.value,
  ))
