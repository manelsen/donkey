## TurnJournalPort — where a turn in flight is recorded, so the next start
## can tell it was interrupted (domain/turn_journal_pure, PRD-roadmap E1).
##
## The adapter is `adapters/state/turn_journal_store`. A nil port means no
## journal: turns run as before and nothing is resumed.

import ../core/pipeops
import ../domain/turn_journal_pure

export turn_journal_pure

type
  TurnJournalPort* = object
    begin*:      proc(r: TurnRecord): Result[void, string] {.gcsafe, raises: [].}
    markEffect*: proc(id, toolName: string): Result[void, string] {.gcsafe, raises: [].}
      ## Before the tool runs (write-ahead).
    finish*:     proc(id: string): Result[void, string] {.gcsafe, raises: [].}
    pending*:    proc(): Result[seq[TurnRecord], string] {.gcsafe, raises: [].}
      ## The turns a previous process left unfinished.

func hasTurnJournal*(p: TurnJournalPort): bool =
  p.begin != nil and p.markEffect != nil and p.finish != nil and p.pending != nil
