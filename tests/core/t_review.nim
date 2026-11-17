## Tests for the self-improvement review: digest, prompt and result parsing.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/core/review/review
import donkey/domain/message

func msg(role, text: string): ChatMessage =
  ChatMessage(role: role, text: text)

suite "review digest":

  test "keeps the last messages in order":
    var history: ConversationHistory = @[]
    for i in 0 ..< 30:
      history.add(msg(roleUser, "u" & $i))
      history.add(msg(roleAssistant, "a" & $i))
    let digest = buildReviewDigest(history, maxMessages = 4)
    check digest.contains("u28")
    check digest.contains("a29")
    check not digest.contains("u0\n")

  test "skips tool and system turns":
    let history: ConversationHistory = @[
      msg(roleSystem, "system prompt"),
      msg(roleUser, "pergunta"),
      msg(roleTool, "tool output"),
      msg(roleAssistant, "resposta"),
    ]
    let digest = buildReviewDigest(history)
    check digest.contains("pergunta")
    check digest.contains("resposta")
    check not digest.contains("system prompt")
    check not digest.contains("tool output")

  test "labels the speakers":
    let digest = buildReviewDigest(@[msg(roleUser, "oi"), msg(roleAssistant, "olá")])
    check digest.contains("User: oi")
    check digest.contains("Assistant: olá")

  test "clips long messages":
    let history: ConversationHistory = @[msg(roleUser, repeat("x", 5000))]
    let digest = buildReviewDigest(history, maxChars = 400)
    check digest.len <= 400 + 40
    check digest.endsWith("…")

  test "empty history yields an empty digest":
    check buildReviewDigest(@[]) == ""

suite "review prompt":

  test "states the store and the grounding rule":
    let prompt = buildReviewPrompt("User: oi", @[])
    check prompt.contains("MEMORY.md")
    check prompt.toLowerAscii.contains("grounded")
    check prompt.contains("JSON")
    check prompt.contains("nothing")

  test "lists the installed skills it may teach":
    let prompt = buildReviewPrompt("User: oi", @["deploy", "postgres"])
    check prompt.contains("deploy")
    check prompt.contains("postgres")
    check prompt.contains("lesson")

  test "embeds the digest":
    check buildReviewPrompt("User: pergunta", @[]).contains("User: pergunta")

suite "review result parsing":

  test "nothing to save":
    let plan = parseReviewPlan("""{"nothing": true}""").get()
    check plan.nothing
    check plan.proposals.len == 0

  test "memory items become proposals":
    let plan = parseReviewPlan(
      """{"memory": ["O deploy usa blue-green.", "O Postgres local roda na 5432."]}""").get()
    check plan.proposals.len == 2
    check plan.proposals[0].target == rtMemory
    check plan.proposals[0].text == "O deploy usa blue-green."

  test "trims, drops empties and dedupes case-insensitively":
    let plan = parseReviewPlan(
      """{"memory": ["  fato  ", "", "FATO", "outro fato"]}""").get()
    check plan.proposals.len == 2
    check plan.proposals[0].text == "fato"
    check plan.proposals[1].text == "outro fato"

  test "caps the number of memory items":
    var items: seq[string]
    for i in 0 ..< 20:
      items.add("\"fato " & $i & "\"")
    let plan = parseReviewPlan("""{"memory": [""" & items.join(",") & "]}").get()
    check plan.proposals.len == MaxReviewItems

  test "caps the length of an item and drops oversized ones":
    let long = repeat("x", MaxReviewChars + 1)
    let plan = parseReviewPlan("""{"memory": [""" & $(%long) & """]}""").get()
    check plan.proposals.len == 0

  test "accepts a fenced JSON block":
    let plan = parseReviewPlan(
      "```json\n{\"memory\": [\"fato\"]}\n```").get()
    check plan.proposals.len == 1

  test "rejects a profile target: the profile belongs to onboarding":
    let plan = parseReviewPlan("""{"memory": ["fato"], "user": ["gosta de azul"]}""")
    check plan.isOk
    check plan.get().proposals.len == 1
    check plan.get().warnings.len >= 1

  test "skill lessons require an installed slug":
    let plan = parseReviewPlan(
      """{"skills": [{"slug": "deploy", "lesson": "Rode o gate antes do push."}]}""",
      allowedSkills = @["deploy"]).get()
    check plan.proposals.len == 1
    check plan.proposals[0].target == rtSkill
    check plan.proposals[0].skill == "deploy"

  test "an unknown skill slug is warned and dropped":
    let plan = parseReviewPlan(
      """{"skills": [{"slug": "inventada", "lesson": "x"}]}""",
      allowedSkills = @["deploy"]).get()
    check plan.proposals.len == 0
    check plan.warnings.len == 1

  test "skill lessons are rejected when no skill store is wired":
    let plan = parseReviewPlan(
      """{"skills": [{"slug": "deploy", "lesson": "x"}]}""").get()
    check plan.proposals.len == 0
    check plan.warnings.len == 1

  test "invalid JSON is an error":
    check parseReviewPlan("not json").isErr
    check parseReviewPlan("{}").isErr
