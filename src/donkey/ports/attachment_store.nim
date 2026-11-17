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
