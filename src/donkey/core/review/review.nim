## review.nim — the self-improvement review: digest, prompt and result.
##
## After a turn the agent can review what it just lived through and keep what
## is durable. The model is asked for a small JSON plan; this module builds the
## digest it reads, the prompt that governs what may be kept, and the parser
## that turns the answer into typed proposals.
##
## The rules are the transferable part of the mechanism: only facts grounded in
## the conversation, one fact per entry, never a one-off request turned into a
## standing preference, never a negative claim about a tool, and never a
## narrative of a failure that was not actually solved.

import std/[json, strutils]
import ../pipeops
import ../../domain/message

const
  MaxReviewItems*   = 5
  MaxReviewChars*   = 280
  MaxDigestChars*   = 6000
  MaxDigestMessage* = 1200

type
  ReviewTarget* = enum
    rtMemory   ## a durable fact about the environment
    rtSkill    ## a lesson for one installed skill

  ReviewProposal* = object
    target*: ReviewTarget
    text*:   string
    skill*:  string   ## slug, for rtSkill

  ReviewPlan* = object
    nothing*:  bool
    proposals*: seq[ReviewProposal]
    warnings*: seq[string]

# ── digest ────────────────────────────────────────────────────────────────────

func clip(text: string; limit: int): string =
  if text.len <= limit:
    return text
  var cut = limit
  while cut > 0 and (ord(text[cut]) and 0xC0) == 0x80:
    dec cut
  text[0 ..< cut] & "…"

func buildReviewDigest*(history: ConversationHistory;
                        maxMessages = 24;
                        maxChars = MaxDigestChars): string =
  ## The recent conversation, speakers labelled, tool turns skipped. Only what
  ## the review needs: the user's asks and what the assistant did about them.
  var lines: seq[string] = @[]
  var start = max(0, history.len - maxMessages)
  for i in start ..< history.len:
    let message = history[i]
    if message.role notin [roleUser, roleAssistant] or message.text.len == 0:
      continue
    let who = if message.role == roleUser: "User" else: "Assistant"
    lines.add(who & ": " & clip(message.text, MaxDigestMessage))
  result = lines.join("\n\n")
  if result.len > maxChars:
    result = clip(result, maxChars)

# ── prompt ────────────────────────────────────────────────────────────────────

const ReviewPromptHead = """
You just finished a conversation. Decide whether anything from it should be
kept for your future self, and answer with JSON only.

## What you may keep

MEMORY.md holds durable facts about the ENVIRONMENT you operate in: project
conventions, tool quirks, config gotchas, paths and endpoints that matter.
The user profile is built by onboarding, not by you - never write facts about
the person.

Rules:
- Keep only facts GROUNDED in this conversation: a user message or a tool
  result you could point to. Never infer traits, skill level, role, mood or
  preferences from tone or topic.
- Never turn a one-off request into a standing preference. A standing rule
  needs "always", "from now on", "remember", or an explicit like/dislike.
- One fact per entry, at most MAXITEMS entries, each under MAXCHARS characters.
- Do not repeat what the repository's AGENTS.md, the system prompt or a tool
  schema already teaches.
- Never keep a negative claim about a tool ("X is broken"), an environment
  failure with no fix (missing binary, unset credential), or a narrative of a
  session that ended without a working method. If the fix is known, keep the
  FIX, not the failure.
- A fact that is already in MEMORY.md is not worth keeping again.
"""

const ReviewPromptSkillsHead = """
## Lessons for installed skills

You may also add a lesson to an INSTALLED skill when this conversation taught a
non-trivial technique, a correction to how the task is done, or a pitfall that
cost time. The lesson is appended to the skill's learned notes and loads with
it, so write a generalizable rule plus one clause of why - not a log of what
happened here.
"""

const ReviewPromptSkillsTail = """
A lesson must name one of those slugs. Never invent a skill.
"""

const ReviewPromptTail = """
## Answer format

JSON only, no prose, no code fence:

{"nothing": true}                       when there is nothing worth keeping
{"memory": ["fact", "fact"]}            environment facts (the usual answer)
{"skills": [{"slug": "name", "lesson": "rule + why"}]}

You may combine "memory" and "skills". Prefer "nothing" over a weak entry, but
do not reach for it as a default: most sessions that produced a correction or a
non-trivial technique have something worth keeping.

## Conversation

"""

func buildReviewPrompt*(digest: string; skills: openArray[string]): string =
  ## The review instructions. `skills` are the installed slugs the review may
  ## teach; an empty list disables the skill half.
  result = ReviewPromptHead
    .replace("MAXITEMS", $MaxReviewItems)
    .replace("MAXCHARS", $MaxReviewChars)
  if skills.len > 0:
    result.add(ReviewPromptSkillsHead)
    result.add("\nAvailable skills: ")
    result.add(skills.join(", "))
    result.add("\n")
    result.add(ReviewPromptSkillsTail)
  result.add(ReviewPromptTail)
  result.add(digest)

# ── result ────────────────────────────────────────────────────────────────────

func jsonPayload(raw: string): string =
  ## The model sometimes wraps its JSON in prose or a fence; take the outermost
  ## object.
  let first = raw.find('{')
  let last = raw.rfind('}')
  if first < 0 or last <= first:
    return ""
  raw[first .. last]

func asStringArray(node: JsonNode): seq[string] =
  if node.isNil or node.kind != JArray:
    return @[]
  for item in node:
    if item.kind == JString:
      result.add(item.getStr)

proc parseReviewPlan*(raw: string;
                      allowedSkills: seq[string] = @[]): Result[ReviewPlan, string] =
  ## Parses the model's answer into proposals. Oversized, empty, duplicated and
  ## unauthorised entries are dropped with a warning; malformed JSON is an
  ## error, because silently keeping nothing would hide a broken review.
  let payload = jsonPayload(raw)
  if payload.len == 0:
    return err("review answer has no JSON object")
  let root = try:
    parseJson(payload)
  except CatchableError as e:
    return err("review answer is not valid JSON: " & e.msg)
  if root.kind != JObject:
    return err("review answer is not a JSON object")
  if not (root.hasKey("nothing") or root.hasKey("memory") or
          root.hasKey("skills") or root.hasKey("user")):
    return err("review answer has no actionable keys")

  var plan = ReviewPlan()
  let nothing = root.getOrDefault("nothing")
  if not nothing.isNil and nothing.kind == JBool and nothing.getBool:
    plan.nothing = true
    return ok(plan)

  var seen: seq[string] = @[]
  for item in asStringArray(root.getOrDefault("memory")):
    let text = item.strip
    if text.len == 0:
      continue
    if text.len > MaxReviewChars:
      plan.warnings.add("dropped an oversized memory entry (" & $text.len & " chars)")
      continue
    let key = text.toLowerAscii
    if key in seen:
      continue
    if plan.proposals.len >= MaxReviewItems:
      plan.warnings.add("dropped entries beyond " & $MaxReviewItems)
      break
    seen.add(key)
    plan.proposals.add(ReviewProposal(target: rtMemory, text: text))

  let userNode = root.getOrDefault("user")
  if not userNode.isNil and userNode.kind == JArray and userNode.len > 0:
    plan.warnings.add("dropped profile entries: the profile is onboarding-owned")

  let skillsNode = root.getOrDefault("skills")
  if not skillsNode.isNil and skillsNode.kind == JArray:
    for item in skillsNode:
      if item.kind != JObject:
        continue
      let slug = item.getOrDefault("slug").getStr("").strip
      let lesson = item.getOrDefault("lesson").getStr("").strip
      if slug.len == 0 or lesson.len == 0:
        continue
      if allowedSkills.len == 0:
        plan.warnings.add("dropped a skill lesson: no skill store is wired")
        continue
      if slug notin allowedSkills:
        plan.warnings.add("dropped a lesson for unknown skill: " & slug)
        continue
      if lesson.len > MaxReviewChars:
        plan.warnings.add("dropped an oversized lesson for " & slug)
        continue
      plan.proposals.add(ReviewProposal(target: rtSkill, text: lesson, skill: slug))

  if plan.proposals.len == 0 and plan.warnings.len == 0:
    plan.nothing = true
  ok(plan)
