## Concrete tool runtime builders for local skill processes.

import ../../core/pipeops
import ../../ports/tool
import ../../config/skills_registry
import deno_skill

proc buildDenoSkillRuntime*(script: string;
                            permissions: seq[string];
                            policy: SkillRuntimePolicy): Result[LoadedToolRuntime, string] {.gcsafe.} =
  let effectivePermissions = validateSkillPermissions(
    permissions, policy.allowNetHosts).valueOr:
      return err(error)
  var client = newDenoSkillAdapter(script, effectivePermissions)
  let schemasRes = client.listTools()
  if schemasRes.isErr:
    return err(schemasRes.error)
  ok(LoadedToolRuntime(
    port: client.toRuntimePort(),
    schemas: schemasRes.value,
  ))
