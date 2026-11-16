## MemoryPort — concept for user workspace read/write.
##
## Implementations: MdFileAdapter (F1), PostgresMemoryAdapter (F6).
## Paddock layout:
##   {paddocksDir}/{uuid}/
##     USER.md        — identity, preferences summary
##     PREFERENCES.md — provider, language, timezone
##     MEMORY.md      — episodic/semantic notes updated per session
##     CONTACTS.md    — known people
##     SOLUTIONS.md   — reusable solutions
##     sessions/      — per-session conversation logs

import std/json
import ../core/pipeops
import ../core/types
import ../domain/memory/episode_pure
import ../domain/memory/provenance_pure
import ../domain/memory/recall_pure
import ../domain/memory/session_search_pure
import ../domain/message
import ../domain/personality

export provenance_pure
export recall_pure  ## MemoryHit and its rendering live in the domain

const
  HeartbeatFileName* = "HEARTBEAT.md"

type
  UserContext* = object
    ## Aggregated context loaded from a paddock for LLM injection.
    userId*:        UserId
    userMd*:        string   ## contents of USER.md   (empty if absent)
    memoryMd*:      string   ## contents of MEMORY.md
    preferencesMd*: string   ## contents of PREFERENCES.md

  MemoryPort* = concept m
    m.hasProfile(UserId) is bool
    ## Returns true iff USER.md (or equivalent) exists for this user.

    m.loadContext(UserId) is UserContext
    ## Loads USER.md + MEMORY.md + PREFERENCES.md into a UserContext.

    m.saveUserMd(UserId, string)
    ## Overwrites USER.md (or equivalent) for the given user.

    m.appendMemory(UserId, string)
    ## Appends a block of text to MEMORY.md (creates if absent).

    m.savePreferences(UserId, string)
    ## Overwrites PREFERENCES.md.

  SemanticMemoryPort* = concept m
    ## MemoryPort extended with hybrid vector + graph search.
    m.hasProfile(UserId) is bool
    m.loadContext(UserId) is UserContext
    m.saveUserMd(UserId, string)
    m.appendMemory(UserId, string)
    m.savePreferences(UserId, string)
    m.search(UserId, string, int) is seq[MemoryHit]

  SearchFn* = proc(userId: UserId; query: string; limit: int): seq[MemoryHit]
    {.gcsafe, raises: [].}
  ## Closure form of the search operation. Nil = no semantic search (fall back to raw MEMORY.md).

  SearchSessionsFn* = proc(userId: UserId; query: string; limit: int;
                           includeMemory: bool): Result[seq[SessionHit], string]
    {.gcsafe, raises: [].}
  ## Closure form of transcript/MEMORY search. Nil = backend without support.

  MemoryRuntimePort* = object
    hasProfile*:      proc(userId: UserId): bool {.gcsafe.}
    loadContext*:     proc(userId: UserId): UserContext {.gcsafe.}
    saveUserMd*:      proc(userId: UserId; content: string) {.gcsafe.}
    appendMemory*:    proc(userId: UserId; text: string) {.gcsafe.}
    ## Optional. Same as appendMemory, recording where the text came from and
    ## reporting whether it was stored. Nil means the backend keeps no
    ## origin; callers fall back to appendMemory.
    appendMemoryFrom*: proc(userId: UserId; text: string;
                            origin: MemoryOrigin): Result[void, string]
                            {.gcsafe, raises: [].}
    savePreferences*: proc(userId: UserId; content: string) {.gcsafe.}
    clearMemory*:     proc(userId: UserId) {.gcsafe.}
    resetBootstrap*:  proc(userId: UserId) {.gcsafe.}
    saveSession*:     proc(userId: UserId; sessionId: string; history: ConversationHistory)
                        {.gcsafe.}
    saveIdentity*:    proc(userId: UserId; traits: PersonalityTraits; name: string)
                        {.gcsafe.}
    loadIdentity*:    proc(userId: UserId): (string, PersonalityTraits)
                        {.gcsafe.}
    searchSessions*:  SearchSessionsFn
    paddockDir*:      proc(userId: UserId): string {.gcsafe.}
    scheduleReminder*:  proc(userId: UserId; channel: string; scheduledAt: int64; message: string): string
                          {.gcsafe.}
    loadDueReminders*:  proc(): seq[JsonNode] {.gcsafe.}
    deleteReminder*:    proc(userId: UserId; reminderId: string) {.gcsafe.}
    ## Optional consolidation hooks. Nil means the backend has no episode
    ## storage and automatic consolidation is skipped.
    appendExtractedMemory*: proc(userId: UserId; text: string): Result[void, string]
                              {.gcsafe, raises: [].}
    saveEpisode*:           proc(userId: UserId; episode: EpisodeJournal): Result[void, string]
                              {.gcsafe, raises: [].}


func hasMemoryConsolidation*(p: MemoryRuntimePort): bool =
  p.appendExtractedMemory != nil and p.saveEpisode != nil

proc bootstrapUserMd*(name, callMe, timezone, language: string): string =
  ## Generates the initial USER.md following the OpenClaw USER.md template.
  """---
summary: """ & name & """ — onboarded via Donkey bootstrapping.
read_when: every conversation
---

# """ & name & """

**Preferred name:** """ & callMe & """
**Timezone:** """ & timezone & """
**Language:** """ & language & """
"""

proc defaultHeartbeatMd*(): string =
  ## New paddocks get an empty HEARTBEAT.md so the file is always present
  ## without scheduling any task by default.
  ""
