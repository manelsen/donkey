## inbound_media.nim — orchestrate inbound attachment metadata and turn markers.
##
## Filesystem writes live in `adapters/filesystem/attachment_store`; this module only
## chooses the marker, updates the message and clears the channel file_id.

import std/[os, strutils]
import results
import ../domain/message
import ../domain/providers/media_pure
import ../ports/channel
import ../ports/attachment_store

type
  InboundAttachment* = object
    relPath*:  string
    absPath*:  string
    mimeType*: string
    size*:     int64
    isImage*:  bool

const ImageMarkerPrefix* = "[Imagem anexada: "

func isImageMime(mime: string): bool =
  mime.toLowerAscii().startsWith("image/")

func imageAttachmentMarker*(relPath: string; inline: bool;
                            mime = ""; size = 0'i64): string =
  ## The one image marker format. `inline` is decided at turn assembly, when
  ## the final inline cap is known; saving an image to disk only knows the
  ## path and must not claim that the bytes accompany the message.
  let head = ImageMarkerPrefix & relPath &
    (if mime.len > 0: " (" & mime & ", " & $size & " bytes)" else: "") & ". "
  if inline:
    head & "A imagem já acompanha esta mensagem; use inspect_image com path=\"" &
      relPath & "\" apenas para ver detalhe (recorte/zoom).]"
  else:
    head & "Use inspect_image com path=\"" & relPath & "\".]"

func stripImageMarkersForPaths*(text: string; paths: openArray[string]): string =
  ## Removes the save-time path markers that the turn builder is about to
  ## replace with markers describing what actually travelled inline. Markers
  ## for paths outside `paths` (for example a non-inlined image) stay.
  var kept: seq[string] = @[]
  for line in text.splitLines():
    var removed = false
    if line.startsWith(ImageMarkerPrefix):
      for path in paths:
        if path.len == 0: continue
        let prefix = ImageMarkerPrefix & path
        if line.startsWith(prefix):
          let after = prefix.len
          if after == line.len or line[after] in {' ', '.'}:
            removed = true
            break
    if not removed:
      kept.add(line)
  while kept.len > 0 and kept[^1].strip.len == 0:
    kept.setLen(kept.len - 1)
  result = kept.join("\n")

func attachmentMarker(relPath, mime: string; size: int64;
                      isImage, visionSupported: bool): string =
  if isImage and visionSupported:
    imageAttachmentMarker(relPath, false, mime, size)
  elif isImage:
    ## `inspect_image` rejects these formats, so the marker must not send the
    ## model to a tool that is guaranteed to fail.
    "[Anexo: " & relPath & " (" & mime & ", " & $size &
      " bytes). Formato de imagem não suportado para visão; use fs_read ou " &
      "text_read para ler o conteúdo.]"
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
  ## annotates `msg.text`, and inlines a supported image as a data URL.
  ## Anything else (non-image, unsupported mime, oversize) keeps
  ## `msg.mediaUrl` empty and the marker points at the disk copy.
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
  let visionSupported =
    image and (mimeType.strip.toLowerAscii() in SupportedImageMimes)

  var mediaUrl = ""
  if visionSupported:
    let inlined = imageDataUrl(mimeType, download.data)
    if inlined.isOk:
      mediaUrl = inlined.get()

  if msg.text.len > 0:
    if not msg.text.endsWith("\n"):
      msg.text.add("\n")
    msg.text.add("\n")
  ## Saving knows the path, not the final turn composition. The inline claim is
  ## written by the turn builder for the images it actually inlines.
  msg.text.add(attachmentMarker(relPath, mimeType, size, image, visionSupported))
  msg.mediaUrl = mediaUrl
  if image and mediaUrl.len > 0:
    ## The payload needs the disk path next to the inline data URL. The original
    ## name was already consumed as the preferred save name above, so reuse the
    ## field as the relative-path carrier from save time to turn assembly.
    msg.mediaFileName = relPath

  ok(InboundAttachment(
    relPath: relPath,
    absPath: saved.get().absPath,
    mimeType: mimeType,
    size: size,
    isImage: image,
  ))
