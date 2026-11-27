## acp_cli — `donkey acp [url]`: Donkey inside an editor (E10.1).
##
## The editor (Zed and others with the Agent Client Protocol) starts this as
## a subprocess and speaks JSON-RPC on its stdin and stdout; nothing else
## may reach stdout. The daemon is reached on its HTTP gateway: the URL is
## the argument, else `DONKEY_ACP_URL`, else `http://127.0.0.1:8080`. For a
## daemon on another machine, put a TLS reverse proxy in front of the gateway
## and use its `https://` URL.
##
## The editor's credential (E10.2) is kept per URL in
## `~/.config/donkey/acp_credentials.json`, written 0600.

import std/[json, os, strutils]
import chronos
import ./core/pipeops
import ./core/app_meta
import ./config/environment
import ./ports/fs
import ./adapters/filesystem/fs_adapter
import ./adapters/acp/gateway_client
import ./app/acp_runtime

const DefaultAcpUrl* = "http://127.0.0.1:8080"

func acpUrl*(env: Environment; args: seq[string]): string =
  if args.len > 0 and args[0].len > 0: args[0]
  elif env.get("DONKEY_ACP_URL").strip.len > 0: env.get("DONKEY_ACP_URL").strip
  else: DefaultAcpUrl

proc readCredentials(fs: FsRuntimePort; path: string): JsonNode =
  if fs.entryKind(path) != fekFile: return newJObject()
  let text = fs.readFile(path).valueOr: return newJObject()
  try:
    let j = parseJson(text)
    if j.kind == JObject: j else: newJObject()
  except CatchableError:
    newJObject()

proc loadCredential*(fs: FsRuntimePort; path, url: string): string =
  readCredentials(fs, path){url}.getStr

proc saveCredential*(fs: FsRuntimePort; path, url, token: string): Result[void, string] =
  ## "" forgets the credential for this URL.
  let old = readCredentials(fs, path)
  var all = newJObject()
  for key, value in old.pairs:
    if key != url: all[key] = value
  if token.len > 0: all[url] = %token
  ? fs.createDir(parentDir(path))
  fs.writePrivate(path, $all)

proc writeLine(line: string) {.gcsafe, raises: [].} =
  try:
    stdout.write(line & "\n")
    stdout.flushFile()
  except IOError:
    discard   ## the editor closed the pipe; the read loop ends next

proc serve(rt: AcpRuntime) {.async: (raises: []).} =
  try:
    let input = fromPipe(AsyncFD(0))
    try:
      while true:
        let line = await input.readLine(sep = "\n")
        if line.len == 0 and input.atEof(): break
        await rt.handleLine(line)
    finally:
      await input.closeWait()
  except CatchableError as e:
    try: stderr.writeLine("donkey acp: " & e.msg)
    except IOError: discard
  await rt.idle()

proc napMs(ms: int): Future[void] {.async: (raises: [CancelledError]).} =
  await sleepAsync(chronos.milliseconds(ms))

proc runAcp*(env: Environment; args: seq[string]): int =
  let url = acpUrl(env, args)
  let client = newGatewayClient(url)
  let fs = newFsAdapter()
  let path = getConfigDir() / "donkey" / "acp_credentials.json"
  let ports = AcpPorts(
    write: writeLine,
    loadToken: proc(): string {.gcsafe, raises: [].} = loadCredential(fs, path, url),
    saveToken: proc(token: string): Result[void, string] {.gcsafe, raises: [].} =
      saveCredential(fs, path, url, token),
    pair: proc(name: string): Future[Result[GatewayPairing, string]] {.async: (raises: []).} =
      return await client.pair(name),
    poll: proc(secret: string): Future[Result[GatewayPoll, string]] {.async: (raises: []).} =
      return await client.poll(secret),
    turn: proc(token, text: string; onLine: LineSink): Future[TurnReply] {.
             async: (raises: [CancelledError]).} =
      return await client.turn(token, text, onLine),
    nap: napMs,
    approve: proc(token, callback: string): Future[Result[string, string]] {.
               async: (raises: []).} =
      return await client.approve(token, callback))
  waitFor serve(newAcpRuntime(ports, AppVersion))
  0
