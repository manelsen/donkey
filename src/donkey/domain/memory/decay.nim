import std/[math, algorithm]
import ../../core/pipeops

## Temporal Decay — Pure logic to decay memory relevance over time
##
## Memory items lose relevance as time passes. Different decay models
## model this differently:
##   - Exponential: score * e^(-λ * t) — fast initial decay, then slow
##   - Linear: score * max(0, 1 - rate * t) — steady decline to zero
##   - HalfLife: score * 0.5^(t / halfLife) — loses half every half-life period

type
  DecayModel* = enum
    dmExponential
    dmLinear
    dmHalfLife

  DecayConfig* = object
    model*: DecayModel
    halfLifeHours*: float   # For dmHalfLife model
    decayRate*: float       # For dmExponential and dmLinear models
    minScore*: float        # Floor to prevent scores from going negative

const
  DefaultHalfLifeHours* = 24.0 * 30.0  ## 30 days in hours
  DefaultDecayRate* = 0.01             ## 1% per hour ≈ 22% per day
  DefaultMinScore* = 0.0001            ## Floor to keep some signal

func exponentialDecay*(initialScore: float; hoursElapsed: float; rate: float): float =
  ## score * e^(-λ * t)
  initialScore * exp(-rate * hoursElapsed)

func linearDecay*(initialScore: float; hoursElapsed: float; rate: float): float =
  ## score * max(0, 1 - rate * t)
  max(0.0, initialScore * (1.0 - rate * hoursElapsed))

func halfLifeDecay*(initialScore: float; hoursElapsed: float; halfLifeHours: float): float =
  ## score * 0.5^(t / halfLife)
  initialScore * pow(0.5, hoursElapsed / halfLifeHours)

func decayScore*(initialScore: float; hoursElapsed: float; config: DecayConfig): float =
  ## Apply the configured decay model to a single score.
  let decayed =
    case config.model
    of dmExponential:
      exponentialDecay(initialScore, hoursElapsed, config.decayRate)
    of dmLinear:
      linearDecay(initialScore, hoursElapsed, config.decayRate)
    of dmHalfLife:
      halfLifeDecay(initialScore, hoursElapsed, config.halfLifeHours)
  max(config.minScore, decayed)

func defaultDecayConfig*: DecayConfig =
  DecayConfig(
    model: dmHalfLife,
    halfLifeHours: DefaultHalfLifeHours,
    decayRate: DefaultDecayRate,
    minScore: DefaultMinScore
  )

func decayedRelevance*(score: float32;
                       timestampSec, nowSec: int64;
                       config = defaultDecayConfig()): float32 =
  ## Applies the configured decay to a stored relevance score. Future
  ## timestamps are treated as fresh (no negative age).
  let hoursElapsed = max(0.0, (nowSec - timestampSec).float / 3600.0)
  (score.float * decayScore(1.0, hoursElapsed, config)).float32


type
  ScoredItem*[T] = object
    item*: T
    score*: float

  DecayedItem*[T] = object
    item*: T
    originalScore*: float
    decayedScore*: float
    hoursElapsed*: float

proc decayScores*[T](
  items: seq[ScoredItem[T]];
  hoursElapsedFn: proc(item: T): float {.gcsafe.};
  config: DecayConfig
): seq[DecayedItem[T]] =
  ## Apply temporal decay to a sequence of scored items.
  ## hoursElapsedFn returns hours since the item was created.
  var result: seq[DecayedItem[T]] = @[]
  for it in items:
    let hours = hoursElapsedFn(it.item)
    result.add(DecayedItem[T](
      item: it.item,
      originalScore: it.score,
      decayedScore: decayScore(it.score, hours, config),
      hoursElapsed: hours
    ))
  result

func decayScores*[T](
  items: seq[tuple[item: T, score: float, hoursElapsed: float]];
  config: DecayConfig
): seq[DecayedItem[T]] =
  ## Apply temporal decay to a sequence of items with pre-computed hours.
  var result: seq[DecayedItem[T]] = @[]
  for it in items:
    result.add(DecayedItem[T](
      item: it.item,
      originalScore: it.score,
      decayedScore: decayScore(it.score, it.hoursElapsed, config),
      hoursElapsed: it.hoursElapsed
    ))
  result

func filterByDecayedScore*[T](
  items: seq[DecayedItem[T]];
  threshold: float
): seq[DecayedItem[T]] =
  ## Keep only items whose decayed score exceeds the threshold.
  var filtered: seq[DecayedItem[T]] = @[]
  for item in items:
    if item.decayedScore >= threshold:
      filtered.add(item)
  filtered

func sortByDecayedScore*[T](
  items: seq[DecayedItem[T]];
  ascending: bool = false
): seq[DecayedItem[T]] =
  ## Sort by decayed score. Default descending (highest relevance first).
  var result = items
  sort(result, proc(a, b: DecayedItem[T]): int =
    if ascending:
      cmp(a.decayedScore, b.decayedScore)
    else:
      cmp(b.decayedScore, a.decayedScore)
  )
  result

func relevanceRatio*[T](item: DecayedItem[T]): float =
  ## Ratio of decayed to original score (1.0 = fresh, 0.0 = completely decayed).
  if item.originalScore <= 0.0: 0.0
  else: item.decayedScore / item.originalScore
