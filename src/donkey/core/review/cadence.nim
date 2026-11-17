## cadence.nim — when the self-improvement review should run.
##
## Two independent counters, mirroring the trigger split used by the reference
## implementation: memory is reviewed every N user turns, skills every N
## tool-calling iterations. Pure state: the caller ticks and consumes.

type
  ReviewCadence* = object
    turnsSinceMemory*: int
    itersSinceSkill*:  int
    memoryInterval*:   int
    skillInterval*:    int

func defaultReviewCadence*(memoryInterval = 10; skillInterval = 0): ReviewCadence =
  ## `skillInterval = 0` disables the skill review: Donkey only learns into
  ## installed skills, so the caller enables it when a skill store is wired.
  ReviewCadence(
    turnsSinceMemory: 0,
    itersSinceSkill:  0,
    memoryInterval:   memoryInterval,
    skillInterval:    skillInterval,
  )

func noteUserTurn*(c: var ReviewCadence) =
  inc c.turnsSinceMemory

func noteToolIterations*(c: var ReviewCadence; count: int) =
  if count > 0:
    c.itersSinceSkill += count

func memoryDue*(c: ReviewCadence): bool =
  c.memoryInterval > 0 and c.turnsSinceMemory >= c.memoryInterval

func skillDue*(c: ReviewCadence): bool =
  c.skillInterval > 0 and c.itersSinceSkill >= c.skillInterval

proc consumeMemory*(c: var ReviewCadence) =
  c.turnsSinceMemory = 0

proc consumeSkill*(c: var ReviewCadence) =
  c.itersSinceSkill = 0
