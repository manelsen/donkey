## code_tools — parsing and execution glue for the `execute_code` tool.
##
## Approval, timeout and output caps are enforced here; the actual container
## argv and process I/O live in `infra/sandbox/code_runner`.

import std/[json, options, os, strutils]

import nimcrypto/sha2
import ../../core/log
import ../../core/pipeops
import ../../core/types
import ../../domain/tools/code_pure
import ../../infra/sandbox/code_runner
import ../sandbox
import ./fs_tools

export code_pure

type
  CodeRuntimeConfig* = object
    sandbox*:        CodeSandboxKind
    runtimeCmd*:     string
    image*:          string
    timeoutSec*:     int
    maxOutputBytes*: int
    maxSourceBytes*: int

  CodeRequest* = object
    language*:   CodeLanguage
    code*:       string
    wasmPath*:   string
    timeoutSec*: int

  CodeExecution* = object
    text*:       string
    exitCode*:   int
    timedOut*:   bool
    truncated*:  bool
    durationMs*: int64

proc sha256hex(data: string): string =
  var ctx: sha256
  ctx.init()
  ctx.update(data)
  let digest = ctx.finish()
  result = ""
  for b in digest.data:
    result.add(toHex(int(b), 2).toLowerAscii())

func codeSandboxFromMode*(mode: SandboxMode): Result[CodeSandboxKind, string] =
  case mode
  of smOci: ok(cskOci)
  of smWasm: ok(cskWasm)
  of smNone:
    err("execute_code requires sandbox.mode='oci' or 'wasm'; host fallback is not allowed")

proc codeConfigFromEnv*(mode: SandboxMode; runtimeCmd: string):
                        Result[CodeRuntimeConfig, string] =
  ## Environment overrides are read once per call so tests and operators can
  ## change limits without reconstructing the daemon.
  let sandbox = codeSandboxFromMode(mode).valueOr:
    return err(error)
  var cfg = CodeRuntimeConfig()
  cfg.sandbox = sandbox
  cfg.runtimeCmd = getEnv("DONKEY_CODE_RUNTIME").strip()
  if cfg.runtimeCmd.len == 0:
    cfg.runtimeCmd =
      if runtimeCmd.len > 0: runtimeCmd
      else: "docker"
  cfg.image = getEnv("DONKEY_CODE_IMAGE").strip()
  cfg.timeoutSec =
    parseCodeTimeoutSec(getEnv("DONKEY_CODE_TIMEOUT_SEC"))
  cfg.maxOutputBytes =
    parseCodeMaxOutputBytes(getEnv("DONKEY_CODE_MAX_OUTPUT_BYTES"))
  cfg.maxSourceBytes =
    parseCodeMaxSourceBytes(getEnv("DONKEY_CODE_MAX_SOURCE_BYTES"))
  ok(cfg)

proc resolveWasmPath(workspace, rawPath: string): Result[string, string] =
  if rawPath.len == 0:
    return err("wasm_path is required for language='wasm'")
  let logical = resolveInPaddock(rawPath, workspace)
  if not inPaddock(logical, workspace):
    return err("wasm_path outside paddock: " & rawPath)
  let canonicalWorkspace = canonicalPath(workspace).valueOr:
    workspace
  let canonical = canonicalPath(logical).valueOr:
    return err(error)
  if not inPaddock(canonical, canonicalWorkspace):
    return err("wasm_path resolves outside paddock: " & rawPath)
  if not fileExists(canonical):
    return err("wasm module not found: " & rawPath)
  let size = regularFileSize(canonical).valueOr:
    return err(error)
  if size <= 0:
    return err("wasm module is empty: " & rawPath)
  if size > CodeMaxWasmBytes:
    return err("wasm module exceeds " & $CodeMaxWasmBytes & " bytes")
  ok(canonical)

proc parseCodeRequest*(input: JsonNode; workspace: string;
                       maxSourceBytes = CodeDefaultMaxSourceBytes;
                       defaultTimeoutSec = CodeDefaultTimeoutSec):
                       Result[CodeRequest, string] =
  let languageNode = input.getOrDefault("language")
  let rawLanguage =
    if languageNode != nil and languageNode.kind == JString:
      languageNode.getStr("").strip()
    else:
      ""
  let languageOpt = parseCodeLanguage(rawLanguage)
  if languageOpt.isNone:
    return err("invalid language; use python, javascript, shell or wasm")
  var req = CodeRequest(language: languageOpt.get())

  let timeoutNode = input.getOrDefault("timeout_sec")
  if timeoutNode != nil and timeoutNode.kind == JInt:
    req.timeoutSec = clampCodeTimeoutSec(timeoutNode.getInt())
  else:
    req.timeoutSec = clampCodeTimeoutSec(defaultTimeoutSec)

  if req.language == clWasm:
    let pathNode = input.getOrDefault("wasm_path")
    let rawPath =
      if pathNode != nil and pathNode.kind == JString:
        pathNode.getStr("").strip()
      else:
        ""
    let resolved = resolveWasmPath(workspace, rawPath)
    if resolved.isErr:
      return err(resolved.error)
    req.wasmPath = resolved.get()
    return ok(req)

  let codeNode = input.getOrDefault("code")
  if codeNode == nil or codeNode.kind != JString:
    return err("code is required for language '" & $req.language & "'")
  req.code = codeNode.getStr("")
  let validated = validateCodeSource(req.language, req.code, maxSourceBytes)
  if validated.isSome:
    return err(validated.get())
  ok(req)

proc runCodeRequest*(req: CodeRequest;
                     cfg: CodeRuntimeConfig;
                     workspace: string;
                     uid: UserId;
                     channel: ChannelKind;
                     log: Logger): Result[CodeExecution, string] =
  ## NOTE: this blocks the tool actor for up to `timeoutSec`, exactly like
  ## `bash`. Moving it to a helper process/thread is an architectural follow-up;
  ## it must not be hidden behind a `gcsafe` cast.
  if cfg.sandbox == cskWasm and req.language != clWasm:
    return err("sandbox.mode='wasm' only supports language='wasm'")
  if cfg.sandbox == cskOci and req.language == clWasm:
    return err("wasm code requires sandbox.mode='wasm'")
  let run = executeCode(
    cfg.sandbox, cfg.runtimeCmd, cfg.image, workspace,
    effectiveUid(), effectiveGid(), req.language, req.code, req.wasmPath,
    req.timeoutSec, cfg.maxOutputBytes)
  let artifactHash =
    if req.language == clWasm:
      fileSha256(req.wasmPath).valueOr: ""
    else:
      sha256hex(req.code)
  let artifactBytes =
    if req.language == clWasm:
      regularFileSize(req.wasmPath).valueOr: 0'i64
    else:
      int64(req.code.len)
  if run.isErr:
    ## The tool result still carries the diagnosis for the requester. The
    ## audit log must not persist program stdout/stderr embedded in
    ## run.error (CWE-532).
    let failureAudit = %*{
      "event": "execute_code",
      "phase": "error",
      "user": $uid,
      "channel": $channel,
      "language": $req.language,
      "sandbox": $cfg.sandbox,
      "code_sha256": artifactHash,
      "code_bytes": artifactBytes,
      "timeout_sec": req.timeoutSec,
      "diagnostic": "execution failed; see tool result",
      "network": false,
    }
    log.warn($failureAudit)
    return err(run.error)
  let res = run.get()
  let text = formatCodeResult(res.output, res.exitCode, res.timedOut,
                              res.truncated)
  let audit = %*{
    "event": "execute_code",
    "user": $uid,
    "channel": $channel,
    "language": $req.language,
    "sandbox": $res.sandbox,
    "image": res.image,
    "code_sha256": artifactHash,
    "code_bytes": artifactBytes,
    "wasm_path": req.wasmPath,
    "timeout_sec": req.timeoutSec,
    "duration_ms": res.durationMs,
    "exit_code": res.exitCode,
    "timed_out": res.timedOut,
    "truncated": res.truncated,
    "output_bytes": res.output.len,
    "network": false,
  }
  log.info($audit)
  ok(CodeExecution(
    text: text,
    exitCode: res.exitCode,
    timedOut: res.timedOut,
    truncated: res.truncated,
    durationMs: res.durationMs,
  ))
