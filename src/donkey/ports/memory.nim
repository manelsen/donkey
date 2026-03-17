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
    userId*:      UserId
    userMd*:      string   ## contents of USER.md   (empty if absent)
    memoryMd*:    string   ## contents of MEMORY.md
    preferencesMd*: string ## contents of PREFERENCES.md

  MemoryPort* = concept m
    m.hasProfile(UserId) is bool
    ## Returns true iff the paddock directory and USER.md exist.

    m.loadContext(UserId) is UserContext
    ## Loads USER.md + MEMORY.md + PREFERENCES.md into a UserContext.

    m.saveUserMd(UserId, string)
    ## Overwrites USER.md for the given user.

    m.appendMemory(UserId, string)
    ## Appends a block of text to MEMORY.md (creates file if absent).

    m.savePreferences(UserId, string)
    ## Overwrites PREFERENCES.md.
