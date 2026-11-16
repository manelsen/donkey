## inbound_media.nim — persist inbound attachments inside the user's paddock.
##
## Channel adapters download bytes; this module decides where they live and
## how the agent learns about them. The file always goes to
## `{paddock}/attachments/`, so the existing fs_* and inspect_image tools can
## reach it without guessing the daemon's working directory.

import std/[os, strutils]
import results
import ../domain/message
import ../ports/channel
import ../core/media_download

const
  AttachmentDirName* = "attachments"

type
  InboundAttachment* = object
    relPath*:  string
    absPath*:  string
    mimeType*: string
    size*:     int64
    isImage*:  bool

func sanitizeAttachmentName*(raw: string): string =
  ## Keeps the user-facing name but removes anything that could escape the
  ## attachments directory or confuse the filesystem.
  var name = raw.strip
  if name.len == 0:
    return "attachment"
  name = name.replace('\\', '/')
  let slash = name.rfind('/')
  if slash >= 0 and slash + 1 < name.len:
    name = name[slash + 1 .. ^1]
  var cleaned = ""
  for ch in name:
    if ch in {'/', '\\', ':', '*', '?', '"', '<', '>', '|'} or ord(ch) < 32:
      cleaned.add('_')
    else:
      cleaned.add(ch)
  cleaned = cleaned.strip(chars = {'.', ' '})
  if cleaned.len == 0 or cleaned == "." or cleaned == "..":
    return "attachment"
  cleaned

proc secureDir(path: string) =
  createDir(path)
  when defined(posix):
    setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})

proc secureFile(path: string) =
  when defined(posix):
    setFilePermissions(path, {fpUserRead, fpUserWrite})

func isImageMime(mime: string): bool =
  mime.toLowerAscii().startsWith("image/")

func attachmentMarker(relPath, mime: string; size: int64; isImage: bool): string =
  if isImage:
    "[Imagem anexada: " & relPath & " (" & mime & ", " & $size &
      " bytes). Use inspect_image com path=\"" & relPath & "\".]"
  else:
    "[Anexo: " & relPath & " (" & mime & ", " & $size &
      " bytes). Use fs_read ou text_read para ler o conteúdo.]"

proc applyInboundAttachment*(msg: var InboundMessage;
                             download: FileDownload;
                             paddockDir: string;
                             preferredName = "";
                             preferredMime = ""): Result[InboundAttachment, string] =
  ## Saves `download` under `{paddockDir}/attachments`, annotates `msg.text`,
  ## clears `msg.mediaUrl` (so a channel file_id never reaches a provider), and
  ## returns the saved attachment metadata.
  try:
    createDir(paddockDir)
    let attachmentsDir = paddockDir / AttachmentDirName
    secureDir(attachmentsDir)

    var fileDownload = download
    let chosenName =
      if preferredName.strip.len > 0: preferredName
      else: fileDownload.fileName
    fileDownload.fileName = sanitizeAttachmentName(chosenName)

    let saveResult = fileDownload.saveFileToDisk(attachmentsDir)
    if saveResult.isErr:
      return err(saveResult.error)

    let absPath = saveResult.value
    secureFile(absPath)
    let slash = absPath.rfind('/')
    let savedName = if slash >= 0: absPath[slash + 1 .. ^1] else: absPath
    let relPath = AttachmentDirName / savedName
    let mimeType =
      if preferredMime.strip.len > 0: preferredMime.strip
      elif fileDownload.mimeType.strip.len > 0: fileDownload.mimeType.strip
      else: "application/octet-stream"
    let size =
      if fileDownload.fileSize > 0: fileDownload.fileSize
      else: fileDownload.data.len.int64
    let image = isImageMime(mimeType)

    if msg.text.len > 0:
      if not msg.text.endsWith("\n"):
        msg.text.add("\n")
      msg.text.add("\n")
    msg.text.add(attachmentMarker(relPath, mimeType, size, image))
    msg.mediaUrl = ""

    ok(InboundAttachment(
      relPath: relPath,
      absPath: absPath,
      mimeType: mimeType,
      size: size,
      isImage: image,
    ))
  except CatchableError as e:
    err("applyInboundAttachment: " & e.msg)
