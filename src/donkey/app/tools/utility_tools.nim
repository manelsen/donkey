## utility_tools.nim — calc, mermaid rendering, and image inspection.
##
## performCalc evaluates mathematical expressions.
## performRenderMermaid converts Mermaid diagrams to SVG.
## performInspectImage uses the LLM as a vision assistant.

import std/[osproc, os, strutils, times, base64]
import results
import ../../domain/calc
import ../../domain/message
import ../../ports/provider

# ── calc ──────────────────────────────────────────────────────────────────────

proc performCalc*(expression: string): string {.gcsafe, raises: [].} =
  try:
    evalCalc(expression)
  except Exception as e:
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
  let ext = splitFile(path).ext.toLowerAscii()
  case ext
  of ".jpg", ".jpeg": "image/jpeg"
  of ".png":          "image/png"
  of ".gif":          "image/gif"
  of ".webp":         "image/webp"
  else:               "image/jpeg"

proc performInspectImage*(path, prompt: string;
                          completeFn: CompleteFn): string {.gcsafe, raises: [].} =
  try:
    if not fileExists(path):
      return "Error: file not found: " & path
    let bytes    = readFile(path)
    let b64      = encode(bytes)
    let mime     = mimeFromExt(path)
    let dataUrl  = "data:" & mime & ";base64," & b64
    let question = if prompt.len > 0: prompt else: "Describe this image in detail."
    var h = newHistory()
    h.addUserWithImage(question, dataUrl)
    let req = buildPrompt("You are a vision assistant.", h, "")
    let resp = completeFn(req)
    if resp.isErr: return "Error: " & resp.error
    resp.value.text
  except Exception as e:
    "Error: " & e.msg
