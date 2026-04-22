import std/unittest

import donkey/domain/message
import donkey/domain/more_tools
import donkey/domain/personality
import donkey/app/prompt_building

suite "prompt building":
  test "buildSystemBase includes tools suffix":
    let systemBase = buildSystemBase(PersonalityTraits(), "", "\n\n## Available tools\n- x")
    check systemBase.contains("Respond in the user's preferred language.")
    check systemBase.contains("## Available tools")

  test "orchToolsSuffix teaches manage_skills for missing capabilities":
    let suffix = orchToolsSuffix(@[
      ToolDescription(
        name: ManageSkillsToolName,
        description: ManageSkillsToolDescription,
        schemaJson: ManageSkillsToolSchema,
      )
    ])
    check suffix.contains("You can install and enable skills")
    check suffix.contains("how skill installation works")
    check suffix.contains("use `manage_skills`")
    check suffix.contains("search/install/enable a skill")
    check suffix.contains("offer to search the registry")
    check suffix.contains("toolset is fixed")
    check suffix.contains("next message")

  test "orchToolsSuffix prefers structured tools before bash":
    let suffix = orchToolsSuffix(@[
      ToolDescription(
        name: BashToolName,
        description: BashToolDescription,
        schemaJson: BashToolSchema,
      ),
      ToolDescription(
        name: FsListToolName,
        description: FsListToolDescription,
        schemaJson: FsListToolSchema,
      ),
      ToolDescription(
        name: TextSearchToolName,
        description: TextSearchToolDescription,
        schemaJson: TextSearchToolSchema,
      ),
      ToolDescription(
        name: JsonQueryToolName,
        description: JsonQueryToolDescription,
        schemaJson: JsonQueryToolSchema,
      ),
      ToolDescription(
        name: TableQueryToolName,
        description: TableQueryToolDescription,
        schemaJson: TableQueryToolSchema,
      ),
      ToolDescription(
        name: HttpFetchToolName,
        description: HttpFetchToolDescription,
        schemaJson: HttpFetchToolSchema,
      ),
      ToolDescription(
        name: ArchiveExtractToolName,
        description: ArchiveExtractToolDescription,
        schemaJson: ArchiveExtractToolSchema,
      ),
    ])
    check suffix.contains("Prefer the structured native tools")
    check suffix.contains("prefer passing structured JSON results between tools")
    check suffix.contains("Use `bash` only when the task truly needs open-ended shell behavior")
    check suffix.contains("instead of `find`, `grep`, `sed`, `sort`, or `bash`")

