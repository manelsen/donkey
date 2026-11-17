## inbound_media.nim — orchestrate inbound attachment metadata and turn markers.
##
## Filesystem writes live in `adapters/filesystem/attachment_store`; this module only
## chooses the marker, updates the message and clears the channel file_id.

import std/[os, strutils]
import results
import ../domain/message
import ../ports/channel
import ../ports/attachment_store

type
  InboundAttachment* = object
    relPath*:  string
    absPath*:  string
    mimeType*: string
    size*:     int64
    isImage*:  bool

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
                             store: AttachmentStorePort;
                             preferredName = "";
                             preferredMime = ""): Result[InboundAttachment, string] =
  ## Persists `download` under `{paddockDir}/attachments` via the store,
  ## annotates `msg.text`, clears `msg.mediaUrl`, and returns the metadata.
  let attachmentsDir = paddockDir / AttachmentDirName
  let chosenName =
    if preferredName.strip.len > 0: preferredName
    else: download.fileName
  let saved = store.save(attachmentsDir, chosenName, download.data)
  if saved.isErr:
    return err(saved.error)

  let relPath = AttachmentDirName / saved.get().fileName
  let mimeType =
    if preferredMime.strip.len > 0: preferredMime.strip
    elif download.mimeType.strip.len > 0: download.mimeType.strip
    else: "application/octet-stream"
  let size =
    if download.fileSize > 0: download.fileSize
    else: download.data.len.int64
  let image = isImageMime(mimeType)

  if msg.text.len > 0:
    if not msg.text.endsWith("\n"):
      msg.text.add("\n")
    msg.text.add("\n")
  msg.text.add(attachmentMarker(relPath, mimeType, size, image))
  msg.mediaUrl = ""

  ok(InboundAttachment(
    relPath: relPath,
    absPath: saved.get().absPath,
    mimeType: mimeType,
    size: size,
    isImage: image,
  ))
