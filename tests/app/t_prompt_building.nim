import std/unittest
import results

import donkey/domain/message
import donkey/domain/more_tools
import donkey/domain/personality
import donkey/app/prompt_building

proc runTests*() =
  suite "prompt building":
    test "buildSystemBase includes tools suffix":
      let systemBase = buildSystemBase(PersonalityTraits(), "", "\n\n## Available tools\n- x")
      check systemBase.contains("Respond in the user's preferred language.")
      check systemBase.contains("## Available tools")

    test "live news requires sources even when no web tool is available":
      let systemBase = buildSystemBase(PersonalityTraits(), "", orchToolsSuffix(@[]))
      check systemBase.contains("consult live sources during this run")
      check systemBase.contains("cite their actual URLs")
      check systemBase.contains("verify that it supports the claim")
      check systemBase.contains("publisher shown on the page")
      check systemBase.contains("check the event date and publication date separately")
      check systemBase.contains("report fewer items")
      check systemBase.contains("If tools are unavailable")
      check systemBase.contains("Never invent headlines")

    test "the tool catalog recommends web search when configured":
      let suffix = orchToolsSuffix(@[ToolDescription(name: WebSearchToolName)])
      check suffix.contains("Use `web_search` to discover current articles")
      check suffix.contains("verify their contents and dates")

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

    test "explainProviderError bypasses LLM paraphrase for tool_call_id errors":
      proc noisyExplainer(req: CompletionRequest): Result[CompletionResponse, string] =
        ok(CompletionResponse(text: "mensagem ruim", inputTokens: 1, outputTokens: 1))

      let explained = explainProviderError(
        noisyExplainer,
        """MiniMax API error 400 Bad Request: {"message":"invalid tool_call_id"}""",
      )
      check explained.contains("sequência longa de ferramentas")
      check not explained.contains("mensagem ruim")

    test "provider errors distinguish attachment and auth/rate-limit failures":
      check "anexo" in genericProviderErrorText(
        """OpenRouter 400: invalid image_url: expected a URL, got file_id""")
      check "autenticação" in genericProviderErrorText("401 Unauthorized")
      check "temporariamente" in genericProviderErrorText("429 rate limit")
      check "anexo" in genericProviderErrorText("unsupported image content")

    test "auth wins when the error also mentions an attachment":
      let text = genericProviderErrorText("401 Unauthorized: attachment type unsupported")
      check "autenticação" in text
      check "anexo" notin text

    test "a pure image rejection still maps to the attachment message":
      let text = genericProviderErrorText(
        """OpenRouter 400: invalid image_url: expected a URL, got file_id""")
      check "anexo" in text
      check "autenticação" notin text

proc runTurnContextTests*() =
  suite "the turn's context (E8.1)":
    test "recall, recent context, commitments and the skills index, in that order":
      let c = assembleTurnContext(recalled = "Ana gosta de chá.", recent = "msg antiga",
                                  commitments = "- ligar amanhã", skills = "## Skills\n- deploy")
      check c.find("Ana gosta") < c.find("## Recent Context")
      check c.find("## Recent Context") < c.find("## Session commitments")
      check c.find("## Session commitments") < c.find("## Skills")
    test "empty parts leave no headings":
      check assembleTurnContext("", "", "", "") == ""
      check assembleTurnContext("", "", "", "## Skills\n- x") == "## Skills\n- x"

when isMainModule:
  runTests()
  runTurnContextTests()
