## review_runtime.nim — the post-turn self-improvement review.
##
## After a turn the agent looks back at what it just lived through and keeps
## the durable part: a fact in MEMORY.md, a lesson in an installed skill. The
## decision of *whether* to look is `core/review/cadence`; this module is the
## app-layer shell that reads the config, calls the model once, and writes the
## accepted proposals through the existing ports.
##
## The review never gets tools: it answers with a small JSON plan, and only
## memory plus installed skills can be written. That keeps an unattended
## background call unable to act on anything else.

import std/[os, strutils, tables]
import chronos
import ../core/log
import ../core/pipeops
import ../core/review/cadence
import ../core/review/review
import ../config/clawhub_registry
import ../domain/memory/provenance_pure
import ../domain/message
import ../ports/memory
import ./provider_executor

const
  ReviewMaxTokens* = 800
  ## Defaults mirror the reference implementation: a memory pass every ten
  ## user turns and a skill pass every ten tool iterations.
  DefaultMemoryInterval* = 10
  DefaultSkillInterval*  = 10

type
  ReviewConfig* = object
    enabled*:        bool
    memoryInterval*: int
    skillInterval*:  int

  ReviewReport* = object
    nothing*:      bool
    memorySaved*:  int
    lessonsSaved*: int
    warnings*:     seq[string]

  ReviewRuntime* = ref object
    config*:    ReviewConfig
    completeFn*: AsyncCompleteFn
    memory*:    MemoryRuntimePort
    homeDir*:   string          ## root that holds `clawhub/skills`
    log*:       Logger
    cadences*:  Table[string, ReviewCadence]
    running*:   Table[string, bool]

# ── config ────────────────────────────────────────────────────────────────────

proc intervalFromEnv(name: string; fallback: int): int =
  ## A missing or unparsable value keeps the default; a parsed zero is
  ## meaningful and disables that half of the review.
  let raw = getEnv(name).strip
  if raw.len == 0:
    return fallback
  try:
    let parsed = raw.parseInt
    if parsed < 0: fallback else: parsed
  except ValueError:
    fallback

proc boolFromEnv(name: string; fallback: bool): bool =
  let raw = getEnv(name).strip.toLowerAscii
  case raw
  of "", "auto": fallback
  of "1", "true", "yes", "on": true
  of "0", "false", "no", "off": false
  else: fallback

proc reviewConfigFromEnv*(): ReviewConfig =
  ## `DONKEY_REVIEW_ENABLED` gates the automatic post-turn pass; an explicit
  ## review (the `/refine` analogue) still works when it is off.
  ReviewConfig(
    enabled:        boolFromEnv("DONKEY_REVIEW_ENABLED", true),
    memoryInterval: intervalFromEnv("DONKEY_REVIEW_MEMORY_INTERVAL", DefaultMemoryInterval),
    skillInterval:  intervalFromEnv("DONKEY_REVIEW_SKILL_INTERVAL", DefaultSkillInterval),
  )

proc skillsHomeFor*(memory: MemoryRuntimePort; userId: UserId): string =
  ## The paddock lives at `{home}/paddocks/{user}`; installed skills live at
  ## `{home}/clawhub/skills`. Returns "" when the backend exposes no paddock.
  if memory.paddockDir == nil:
    return ""
  let paddock = memory.paddockDir(userId)
  if paddock.len == 0:
    return ""
  parentDir(parentDir(paddock))

proc newReviewRuntime*(config: ReviewConfig; completeFn: AsyncCompleteFn;
                       memory: MemoryRuntimePort; homeDir: string;
                       log: Logger): ReviewRuntime =
  ReviewRuntime(
    config: config,
    completeFn: completeFn,
    memory: memory,
    homeDir: homeDir,
    log: log,
    cadences: initTable[string, ReviewCadence](),
    running: initTable[string, bool](),
  )

# ── the review itself ─────────────────────────────────────────────────────────

proc installedSlugs(homeDir: string): seq[string] =
  if homeDir.len == 0:
    return @[]
  for skill in loadInstalledRemoteSkills(homeDir):
    result.add(skill.slug)

proc runReview*(rt: ReviewRuntime; userId: UserId; sessionId: string;
                history: ConversationHistory): Future[Result[ReviewReport, string]] {.async.} =
  ## One review pass: build the digest, ask the model for a plan, apply it.
  ## The model is called even when nothing may be written, but it is not
  ## called for an empty digest. A malformed answer is an error, never a
  ## silent "nothing to keep".
  var report = ReviewReport()
  if rt.completeFn == nil:
    return err("review completion is unavailable")
  let digest = buildReviewDigest(history)
  if digest.strip.len == 0:
    report.nothing = true
    return ok(report)

  let slugs = installedSlugs(rt.homeDir)
  let request = CompletionRequest(
    system: "You are the agent reviewing its own finished conversation.",
    messages: @[ChatMessage(role: roleUser,
                            text: buildReviewPrompt(digest, slugs))],
    maxTokens: ReviewMaxTokens,
  )
  let response = await safeAsyncComplete(rt.completeFn, request)
  if response.isErr:
    return err("review completion: " & response.error)

  let parsed = parseReviewPlan(response.get().text, allowedSkills = slugs)
  if parsed.isErr:
    return err(parsed.error)
  let plan = parsed.get()
  report.nothing = plan.nothing
  report.warnings = plan.warnings
  if plan.nothing or plan.proposals.len == 0:
    return ok(report)

  let origin = MemoryOrigin(source: msReview, sessionId: sessionId)
  for proposal in plan.proposals:
    case proposal.target
    of rtMemory:
      let written = appendMemoryWithOriginChecked(rt.memory, userId,
                                                  proposal.text, origin)
      if written.isOk:
        inc report.memorySaved
      else:
        report.warnings.add("memory write failed: " & written.error)
    of rtSkill:
      let skillDir = remoteSkillDir(rt.homeDir, proposal.skill)
      let written = appendLearnedNote(skillDir, proposal.text)
      if written.isOk:
        inc report.lessonsSaved
      else:
        report.warnings.add("lesson write failed for " & proposal.skill &
                            ": " & written.error)
  ok(report)

# ── cadence and coalescing ────────────────────────────────────────────────────

func isRunning*(rt: ReviewRuntime; userId: UserId): bool =
  rt.running.getOrDefault($userId, false)

proc afterTurn*(rt: ReviewRuntime; userId: UserId; sessionId: string;
                history: ConversationHistory; toolIterations: int): bool =
  ## Ticks the counters for a finished user turn and starts the review when it
  ## is due. At most one review per user runs at a time: a turn that arrives
  ## while one is running leaves the cadence due, so the next turn picks it up.
  ## Returns true when a review was started.
  if rt.completeFn == nil:
    return false
  let key = $userId
  var cadence = rt.cadences.getOrDefault(
    key, defaultReviewCadence(rt.config.memoryInterval, rt.config.skillInterval))
  # The config may have changed since this user's row was created.
  cadence.memoryInterval = rt.config.memoryInterval
  cadence.skillInterval = rt.config.skillInterval
  cadence.noteUserTurn()
  cadence.noteToolIterations(toolIterations)

  if not rt.config.enabled or not (cadence.memoryDue or cadence.skillDue):
    rt.cadences[key] = cadence
    return false
  if rt.isRunning(userId):
    # Do not consume: the work is still owed.
    rt.cadences[key] = cadence
    return false

  if cadence.memoryDue:
    cadence.consumeMemory()
  if cadence.skillDue:
    cadence.consumeSkill()
  rt.cadences[key] = cadence
  rt.running[key] = true

  let rtRef = rt
  asyncSpawn (proc () {.async.} =
    try:
      let outcome = await rtRef.runReview(userId, sessionId, history)
      if outcome.isErr:
        rtRef.log.warn("review for " & key & ": " & outcome.error)
      else:
        let report = outcome.get()
        for warning in report.warnings:
          rtRef.log.warn("review for " & key & ": " & warning)
    finally:
      rtRef.running[key] = false
  )()
  true
