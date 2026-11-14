## SubagentWorkspacePort — fallible filesystem setup for child paddocks.
##
## The composition root wires the implementation; the app layer only sees
## callbacks that return Result and never performs filesystem I/O itself.

import ../core/pipeops

type
  CreateSubagentWorkspaceFn* = proc(root, subagentId: string):
      Result[string, string] {.gcsafe, raises: [].}
    ## Creates {root}/subagents/{subagentId} with user-only permissions and
    ## returns the child paddock path. Fails closed on any I/O error.

  RemoveSubagentWorkspaceFn* = proc(path: string):
      Result[void, string] {.gcsafe, raises: [].}
    ## Removes a child paddock. Missing paths are a success; failures are
    ## reported so the caller can log the orphan.

  SubagentWorkspacePort* = object
    create*: CreateSubagentWorkspaceFn
    remove*: RemoveSubagentWorkspaceFn

func hasSubagentWorkspace*(port: SubagentWorkspacePort): bool =
  port.create != nil and port.remove != nil
