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

import ../core/types

type
  UserContext* = object
    ## Aggregated context loaded from a paddock for LLM injection.
    userId*:        UserId
    userMd*:        string   ## contents of USER.md   (empty if absent)
    memoryMd*:      string   ## contents of MEMORY.md
    preferencesMd*: string   ## contents of PREFERENCES.md

  MemoryHit* = object
    ## Single result from a semantic search.
    content*: string
    score*:   float32  ## cosine similarity [0, 1]; higher = more similar
    kind*:    string   ## node kind: "memory", "fact", "user_profile", etc.

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
