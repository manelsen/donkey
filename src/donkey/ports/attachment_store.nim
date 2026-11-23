## AttachmentStorePort — channel attachments persisted inside a paddock.
##
## The app layer chooses names/metadata; the I/O implementation owns directory
## creation, symlink containment, permissions and collision handling.

import ../core/pipeops

const AttachmentDirName* = "attachments"

type
  SavedAttachment* = object
    fileName*: string
    absPath*:  string

  AttachmentStorePort* = object
    save*: proc(directory, fileName: string; data: seq[byte]):
            Result[SavedAttachment, string] {.gcsafe, raises: [].}

func unavailableAttachments*(): AttachmentStorePort =
  ## Fail-closed default: a zeroed proc field would crash.
  AttachmentStorePort(save: proc(directory, fileName: string; data: seq[byte]):
      Result[SavedAttachment, string] {.gcsafe, raises: [].} =
    err("attachment store unavailable"))

func orUnavailable*(p: AttachmentStorePort): AttachmentStorePort =
  if p.save == nil: unavailableAttachments() else: p
