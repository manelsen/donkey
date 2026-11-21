## utility_tools.nim — calc, mermaid rendering, and image inspection.
##
## performCalc evaluates mathematical expressions.
## performRenderMermaid converts Mermaid diagrams to SVG.
## performInspectImage uses the LLM as a vision assistant.

import std/[osproc, os, strutils, times]
import results
import ../../domain/calc
import ../../domain/message
import ../../domain/providers/media_pure
import ../../ports/provider

# ── calc ──────────────────────────────────────────────────────────────────────

proc performCalc*(expression: string): string {.gcsafe, raises: [].} =
  try:
    evalCalc(expression)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    "Error: " & e.msg

# ── render_mermaid ────────────────────────────────────────────────────────────

const MermaidTempPrefix* = "donkey_mermaid_"

proc performRenderMermaid*(diagram: string): string {.gcsafe, raises: [].} =
  let ts    = $getTime().toUnix()
  let inF   = "/tmp/" & MermaidTempPrefix & ts & ".mmd"
  let outF  = "/tmp/" & MermaidTempPrefix & ts & ".svg"
  try:
    writeFile(inF, diagram)
    let (_, code) = execCmdEx("mmdc -i " & inF & " -o " & outF,
                               options = {poEvalCommand})
    if code == 0 and fileExists(outF):
      return "Diagram rendered: " & outF
    else:
      return "```mermaid\n" & diagram & "\n```\n" &
             "(install mmdc via `npm i -g @mermaid-js/mermaid-cli` for SVG output)"
  except CatchableError:
    return "```mermaid\n" & diagram & "\n```"
  finally:
    discard tryRemoveFile(inF)

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

proc performInspectImage*(path, prompt: string;
                          completeFn: CompleteFn): string {.gcsafe, raises: [].} =
  try:
    if not fileExists(path):
      return "Error: file not found: " & path
    let mime = mimeFromExt(path)
    if mime.len == 0 or mime notin SupportedImageMimes:
      return "Error: unsupported image type " & splitFile(path).ext
    # Check the encoded budget before reading: base64 grows by ~4/3.
    let rawSize = getFileSize(path)
    let maxRaw = MaxInlineImageEncodedBytes * 3 div 4
    if rawSize <= 0 or rawSize > maxRaw:
      return "Error: image file too large to inline (" & $rawSize & " raw bytes)"
    ## Read with the cap applied: the file can grow between the size check and
    ## the read, and `readFile` would allocate the whole thing.
    var handle: File
    if not open(handle, path):
      return "Error: cannot read image " & splitFile(path).ext
    defer: close(handle)
    var bytes = newString(maxRaw + 1)
    let read = readBuffer(handle, addr bytes[0], maxRaw + 1)
    if read > maxRaw:
      return "Error: image file too large to inline (" & $read & " raw bytes)"
    bytes.setLen(read)
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
