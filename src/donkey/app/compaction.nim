## Compaction (E8.5), the shell: the model's context window from the catalog,
## and the session's own model writing the summary of the old part
## (domain/compaction_pure decides when and where to cut).

import std/[options, strutils]
import chronos
import ../core/pipeops
import ../core/providers/provider_catalog
import ../domain/compaction_pure
import ../domain/message
import ./provider_executor

proc contextWindowOf*(label: string): int =
  ## A route label is `provider/model` (or `auto`); the catalog knows models
  ## by name. 0 when unknown.
  if label.len == 0: return 0
  let catalog = buildDefaultCatalog()
  var keys = @[label]
  let slash = label.find('/')
  if slash > 0: keys.add label[slash + 1 .. ^1]
  for key in keys:
    let entry = catalog.lookup(key)
    if entry.isSome and entry.get.contextWindow > 0:
      return entry.get.contextWindow
  0

proc compactHistory*(callModel: AsyncCompleteFn; history: ConversationHistory;
                     keepTokens: int): Future[Result[ConversationHistory, string]] {.async.} =
  ## The summary of the old part, then the tail as it was. On any failure
  ## the caller keeps the history it had.
  let (old, tail) = splitForCompaction(history, keepTokens)
  if old.len == 0:
    return err(Result[ConversationHistory, string], "nothing old enough to compact")
  if callModel == nil:
    return err(Result[ConversationHistory, string], "compaction: no model available")
  let resp =
    try:
      await callModel(summaryRequest(old))
    except CancelledError as e: raise e
    except Exception as e:  ## effect boundary: callee raises are unannotated
      return err(Result[ConversationHistory, string], "compaction: " & e.msg)
  if resp.isErr:
    return err(Result[ConversationHistory, string], "compaction: " & resp.error)
  if resp.get.text.strip.len == 0:
    return err(Result[ConversationHistory, string], "compaction: the summary came back empty")
  return ok(compactedHistory(resp.get.text, tail))
