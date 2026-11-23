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
    hasProfile*:      proc(userId: UserId): bool {.gcsafe, raises: [].}
      ## False when the profile cannot be read.
    loadContext*:     proc(userId: UserId): UserContext {.gcsafe, raises: [].}
      ## An empty context for the user when nothing can be read.
    ## Writes report whether they were stored: with a graph configured but
    ## unavailable nothing is written, and the caller must be able to tell.
    saveUserMd*:      proc(userId: UserId; content: string): Result[void, string]
                        {.gcsafe, raises: [].}
    appendMemory*:    proc(userId: UserId; text: string): Result[void, string]
                        {.gcsafe, raises: [].}
    ## Optional. Same as appendMemory, recording where the text came from and
    ## reporting whether it was stored. Nil means the backend keeps no
    ## origin; callers fall back to appendMemory.
    appendMemoryFrom*: proc(userId: UserId; text: string;
                            origin: MemoryOrigin): Result[void, string]
                            {.gcsafe, raises: [].}
    savePreferences*: proc(userId: UserId; content: string): Result[void, string]
                        {.gcsafe, raises: [].}
    ## PREFERENCES.md as the store holds it, for a caller that will write
    ## back what it read: an error when the store cannot be read, never a
    ## stale copy that would overwrite newer data.
    storedPreferences*: proc(userId: UserId): Result[string, string]
                          {.gcsafe, raises: [].}
    clearMemory*:     proc(userId: UserId): Result[void, string]
                        {.gcsafe, raises: [].}
    resetBootstrap*:  proc(userId: UserId): Result[void, string]
                        {.gcsafe, raises: [].}
    saveSession*:     proc(userId: UserId; sessionId: string; history: ConversationHistory):
                        Result[void, string] {.gcsafe, raises: [].}
    searchSessions*:  SearchSessionsFn
    paddockDir*:      proc(userId: UserId): string {.gcsafe, raises: [].}
    ## Optional consolidation hooks. Nil means the backend has no episode
    ## storage and automatic consolidation is skipped.
    appendExtractedMemory*: proc(userId: UserId; text: string): Result[void, string]
                              {.gcsafe, raises: [].}
    saveEpisode*:           proc(userId: UserId; episode: EpisodeJournal): Result[void, string]
                              {.gcsafe, raises: [].}


func hasMemoryConsolidation*(p: MemoryRuntimePort): bool =
  p.appendExtractedMemory != nil and p.saveEpisode != nil

proc appendMemoryChecked*(p: MemoryRuntimePort; userId: UserId; text: string):
                          Result[void, string] {.gcsafe, raises: [].} =
  ## appendMemory for a port that may have been built without the hook.
  if p.appendMemory == nil:
    return err("memory backend unavailable")
  p.appendMemory(userId, text)

proc saveAgentIdentity*(p: MemoryRuntimePort; userId: UserId;
                        traits: PersonalityTraits; name: string):
                        Result[void, string] {.gcsafe, raises: [].} =
  ## The agent's identity lives in the preferences: read them as stored,
  ## merge, write back. Nothing is written when they cannot be read.
  if p.storedPreferences == nil or p.savePreferences == nil:
    return err("memory backend unavailable")
  let current = ? p.storedPreferences(userId)
  p.savePreferences(userId, current.withAgentIdentity(traits, name))

proc loadAgentIdentity*(p: MemoryRuntimePort; userId: UserId):
                        (string, PersonalityTraits) {.gcsafe, raises: [].} =
  ## The agent's name and traits, empty when there are none. When the store
  ## cannot be read, the preferences of the loaded context answer instead.
  if p.storedPreferences != nil:
    let stored = p.storedPreferences(userId)
    if stored.isOk:
      return agentIdentityOf(stored.get)
  if p.loadContext == nil:
    return ("", PersonalityTraits())
  agentIdentityOf(p.loadContext(userId).preferencesMd)

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

proc appendMemoryWithOriginChecked*(p: MemoryRuntimePort; userId: UserId;
                                    text: string; origin: MemoryOrigin):
                                    Result[void, string] {.gcsafe, raises: [].} =
  ## Prefers the origin-aware hook when the backend records provenance;
  ## otherwise falls back to the plain append. Both hooks report
  ## failures through `Result`, so no exception crosses this boundary.
  if p.appendMemoryFrom != nil:
    return p.appendMemoryFrom(userId, text, origin)
  p.appendMemoryChecked(userId, text)
