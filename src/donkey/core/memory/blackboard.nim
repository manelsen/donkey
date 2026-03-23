## blackboard.nim - Short-term Planning Memory (Blackboard Pattern).
##
## A session-scoped scratchpad for transient planning data that gets
## injected into LLM context. Unlike persistent memories, the blackboard
## is ephemeral — cleared when the session ends.
##
## The "blackboard" metaphor: multiple agents (or a single orchestrating
## agent) write and read from a shared planning space to coordinate
## complex multi-step tasks.
##
## Usage:
##   var bb = newBlackboard()
##   discard bb.addEntry("current_task", "Implement login flow", PriorityHigh)
##   discard bb.addEntry("constraint", "Must use existing user table")
##   echo bb.render()  # Returns formatted string for context injection

import std/[strutils, algorithm, options]
import ../../core/pipeops

type
  Priority* = enum
    PriorityCritical
    PriorityHigh
    PriorityMedium
    PriorityLow

  BlackboardEntry* = object
    key*: string
    content*: string
    priority*: Priority
    createdAt*: int64  ## monotonic ms from pipeops.nowMs()

  Blackboard* = object
    entries*: seq[BlackboardEntry]
    maxEntries*: int  ## 0 = unlimited

const
  DefaultMaxBlackboardEntries* = 50

# ── Constructors ─────────────────────────────────────────────────────────────

func newBlackboard*(maxEntries = DefaultMaxBlackboardEntries): Blackboard =
  Blackboard(entries: @[], maxEntries: maxEntries)

func newEntry*(key: string; content: string; priority: Priority; createdAt: int64): BlackboardEntry =
  BlackboardEntry(key: key, content: content, priority: priority, createdAt: createdAt)

# ── Pure helpers ─────────────────────────────────────────────────────────────

func priorityOrder*(p: Priority): int =
  case p
  of PriorityCritical: 0
  of PriorityHigh:      1
  of PriorityMedium:    2
  of PriorityLow:      3

func compareEntries*(a, b: BlackboardEntry): int =
  ## For sorting: critical first, then by key
  let p = priorityOrder(a.priority) - priorityOrder(b.priority)
  if p != 0: p
  elif a.key < b.key: -1
  elif a.key > b.key: 1
  else: 0

func entryKeys*(bb: Blackboard): seq[string] =
  result = @[]
  for e in bb.entries:
    result.add(e.key)

func hasEntry*(bb: Blackboard; key: string): bool =
  for e in bb.entries:
    if e.key == key:
      return true
  false

func getEntry*(bb: Blackboard; key: string): Option[BlackboardEntry] =
  for e in bb.entries:
    if e.key == key:
      return some(e)
  return none(BlackboardEntry)

func filterByPrefix*(bb: Blackboard; prefix: string): seq[BlackboardEntry] =
  result = @[]
  for e in bb.entries:
    if e.key.startsWith(prefix):
      result.add(e)

func filterByPriority*(bb: Blackboard; p: Priority): seq[BlackboardEntry] =
  result = @[]
  for e in bb.entries:
    if e.priority == p:
      result.add(e)

func sortEntries*(entries: seq[BlackboardEntry]): seq[BlackboardEntry] =
  sorted(entries, compareEntries)

# ── Formatting for context injection ─────────────────────────────────────────

func formatEntry*(e: BlackboardEntry): string =
  let marker = case e.priority
    of PriorityCritical: "[!]"
    of PriorityHigh:      "[+]"
    of PriorityMedium:    "[-]"
    of PriorityLow:       "[.]"
  marker & " " & e.key & ": " & e.content

func render*(bb: Blackboard; title = "BLACKBOARD"): string =
  if bb.entries.len == 0:
    return "# " & title & "\n_(empty)_\n"
  var lines: seq[string] = @[]
  for e in sortEntries(bb.entries):
    lines.add(formatEntry(e))
  "# " & title & "\n" & lines.join("\n") & "\n"

func renderForUser*(bb: Blackboard): string =
  if bb.entries.len == 0:
    return ""
  var lines: seq[string] = @[]
  for e in sortEntries(bb.entries):
    lines.add(e.content)
  lines.join("\n")

# ── Fallible operations (return Result) ─────────────────────────────────────

proc addEntry*(bb: var Blackboard; key: string; content: string;
               priority: Priority; createdAt: int64): Result[void, string] =
  if key.len == 0:
    return err("blackboard entry key cannot be empty")
  if bb.hasEntry(key):
    return err("blackboard already has entry with key: " & key)
  if bb.maxEntries > 0 and bb.entries.len >= bb.maxEntries:
    return err("blackboard is full (max " & $bb.maxEntries & " entries)")
  let entry = newEntry(key, content, priority, createdAt)
  bb.entries.add(entry)
  ok()

proc updateEntry*(bb: var Blackboard; key: string; content: string;
                  priority: Priority): Result[void, string] =
  for i, e in bb.entries:
    if e.key == key:
      bb.entries[i] = newEntry(key, content, priority, e.createdAt)
      return ok()
  err("blackboard has no entry with key: " & key)

proc removeEntry*(bb: var Blackboard; key: string): Result[void, string] =
  for i, e in bb.entries:
    if e.key == key:
      bb.entries.delete(i)
      return ok()
  err("blackboard has no entry with key: " & key)

proc clear*(bb: var Blackboard) =
  bb.entries.setLen(0)

# ── Overloaded procs with nowMs() default ───────────────────────────────────

proc addEntry*(bb: var Blackboard; key: string; content: string;
               priority: Priority = PriorityMedium): Result[void, string] =
  bb.addEntry(key, content, priority, nowMs())

# ── Chained operations via >>= ───────────────────────────────────────────────

proc addEntryChain*(bb: var Blackboard; key, content: string;
                    priority: Priority): Result[BlackboardEntry, string] =
  let r = bb.addEntry(key, content, priority, nowMs())
  if r.isErr:
    return err(r.error)
  let entry = bb.getEntry(key)
  if entry.isNone:
    return err("failed to retrieve entry after add")
  ok(entry.get())
