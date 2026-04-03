## Contemplation — low-priority idle consolidation into episode journals.
##
## This module intentionally stays outside the synchronous request path.
## Callers can schedule it on heartbeat or any other background trigger.

import std/strutils
import ../core/types
import ../domain/memory/episode_pure
import ./heartbeat

type
  ContemplationConfig* = object
    enabled*:  bool
    provider*: string
    model*:    string

  ContemplationMemory* = object
    id*:        string
    content*:   string
    timestamp*: int64

  ContemplationLoader* = proc(): seq[ContemplationMemory] {.gcsafe.}
  ContemplationBuilder* = proc(memories: seq[ContemplationMemory]): EpisodeJournal {.gcsafe.}
  EpisodeWriter* = proc(userId: UserId; episode: EpisodeJournal) {.gcsafe.}
  UserIdLoader* = proc(): UserId {.gcsafe.}

func usesLowCostOrLocalPath*(cfg: ContemplationConfig): bool =
  let provider = cfg.provider.toLowerAscii()
  let model = cfg.model.toLowerAscii()
  provider in ["ollama", "lmstudio", "local"] or
    model.contains("ollama") or model.contains("lmstudio") or
    model.contains("local") or model.contains("mini") or
    model.contains("small") or model.contains("3b") or
    model.contains("1.5b")

func shouldRunContemplation*(cfg: ContemplationConfig): bool =
  cfg.enabled and cfg.usesLowCostOrLocalPath

proc runContemplationTurn*(cfg: ContemplationConfig;
                           loadMemories: ContemplationLoader;
                           buildEpisode: ContemplationBuilder;
                           writeEpisode: EpisodeWriter;
                           loadUserId: UserIdLoader) =
  if not shouldRunContemplation(cfg):
    return
  if loadMemories == nil or buildEpisode == nil or writeEpisode == nil or loadUserId == nil:
    return
  let memories = loadMemories()
  if memories.len == 0:
    return
  let episode = buildEpisode(memories)
  if episode.summary.len == 0 and episode.title.len == 0:
    return
  try:
    writeEpisode(loadUserId(), episode)
  except CatchableError:
    discard

proc registerContemplationTask*(reg: var HeartbeatRegistry;
                                cfg: ContemplationConfig;
                                loadMemories: ContemplationLoader;
                                buildEpisode: ContemplationBuilder;
                                writeEpisode: EpisodeWriter;
                                loadUserId: UserIdLoader) =
  reg.registerTask("contemplation", proc() {.gcsafe.} =
    runContemplationTurn(cfg, loadMemories, buildEpisode, writeEpisode, loadUserId)
  )
