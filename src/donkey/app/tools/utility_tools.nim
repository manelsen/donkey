## utility_tools.nim — calc, mermaid rendering, and image inspection.
##
## performCalc evaluates mathematical expressions.
## performRenderMermaid converts Mermaid diagrams to SVG.
## performInspectImage uses the LLM as a vision assistant.

import std/[os, strutils, times]
import ../../core/pipeops
import ../../domain/calc
import ../../domain/message
import ../../domain/providers/media_pure
import ../../ports/provider
import ../../ports/fs
import ../../ports/process

# ── calc ──────────────────────────────────────────────────────────────────────

proc performCalc*(expression: string): string {.gcsafe, raises: [].} =
  try:
    evalCalc(expression)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    "Error: " & e.msg

# ── render_mermaid ────────────────────────────────────────────────────────────

const MermaidTempPrefix* = "donkey_mermaid_"

proc performRenderMermaid*(process: ProcessRuntimePort; fs: FsRuntimePort;
                           diagram: string): string {.gcsafe, raises: [].} =
  let ts    = $getTime().toUnix()
  let inF   = "/tmp/" & MermaidTempPrefix & ts & ".mmd"
  let outF  = "/tmp/" & MermaidTempPrefix & ts & ".svg"
  let fallback = "```mermaid\n" & diagram & "\n```"
  if fs.writeFile(inF, diagram).isErr:
    return fallback
  defer: discard fs.remove(inF, false)
  let ran = process.run(argvSpec(@["mmdc", "-i", inF, "-o", outF]))
  if ran.isOk and ran.get.exitCode == 0 and fs.entryKind(outF) == fekFile:
    "Diagram rendered: " & outF
  else:
    fallback & "\n" &
      "(install mmdc via `npm i -g @mermaid-js/mermaid-cli` for SVG output)"

# ── inspect_image ─────────────────────────────────────────────────────────────

proc mimeFromExt(path: string): string =
  ## Empty when the extension is not an image the providers agree to inline.
  ## Guessing `image/jpeg` sent raw SVG/BMP/HEIC bytes labelled as JPEG.
  let ext = splitFile(path).ext.toLowerAscii()
  case ext
  of ".jpg", ".jpeg": "image/jpeg"
  of ".png":          "image/png"
  of ".gif":          "image/gif"
  of ".webp":         "image/webp"
  else:               ""

proc performInspectImage*(fs: FsRuntimePort; path, prompt: string;
                          completeFn: CompleteFn): string {.gcsafe, raises: [].} =
  try:
    if fs.entryKind(path) != fekFile:
      return "Error: file not found: " & path
    let mime = mimeFromExt(path)
    if mime.len == 0 or mime notin SupportedImageMimes:
      return "Error: unsupported image type " & splitFile(path).ext
    # Check the encoded budget before reading: base64 grows by ~4/3.
    let rawSize = fs.fileSize(path).valueOr:
      return "Error: " & error
    let maxRaw = MaxInlineImageEncodedBytes * 3 div 4
    if rawSize <= 0 or rawSize > maxRaw:
      return "Error: image file too large to inline (" & $rawSize & " raw bytes)"
    ## Read with the cap applied: the file can grow between the size check and
    ## the read.
    let bytes = fs.readCapped(path, maxRaw).valueOr:
      return "Error: image file too large to inline (" & error & ")"
    let encoded  = imageDataUrl(mime, bytes.toOpenArrayByte(0, bytes.high))
    if encoded.isErr:
      return "Error: " & encoded.error
    let dataUrl  = encoded.value
    let question = if prompt.len > 0: prompt else: "Describe this image in detail."
    var h = newHistory()
    h.addUserWithImage(question, dataUrl)
    let req = buildPrompt("You are a vision assistant.", h, "")
    let resp = completeFn(req)
    if resp.isErr: return "Error: " & resp.error
    resp.value.text
  except Exception as e:  ## effect boundary: callee raises are unannotated
    "Error: " & e.msg
