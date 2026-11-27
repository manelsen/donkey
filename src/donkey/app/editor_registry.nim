## editor_registry — the daemon's side of pairing editors (E10.2).
##
## Pending pairings live in memory (a restart drops them; the editor asks
## again); credentials live in `state/editors.json`, written 0600 with the
## token's hash only. The gateway and the channels' `/editor` command run on
## the daemon loop's thread, so the registry is a plain shared ref.

import std/[base64, json, strutils]
import ../core/pipeops
import ../core/types
import ../domain/acp/editor_pairing_pure
import ../domain/acp/editor_credentials_pure
import ../ports/fs

type
  RandomBytesFn* = proc(n: int): Result[seq[byte], string] {.gcsafe, raises: [].}
  ClockMsFn* = proc(): int64 {.gcsafe, raises: [].}

  EditorRegistry* = ref object
    fs: FsRuntimePort
    path: string
    random: RandomBytesFn
    now: ClockMsFn
    pairings: EditorPairings
    creds: seq[EditorCredential]

  PairingStarted* = object
    secret*, code*: string

  PairingCollected* = object
    state*: EditorPairingState
    token*: string      ## only when confirmed, once

proc randomText(r: EditorRegistry; n: int): Result[string, string] =
  let bytes = ? r.random(n)
  var raw = newString(bytes.len)
  for i, b in bytes: raw[i] = char(b)
  ok(base64.encode(raw, safe = true).strip(leading = false, chars = {'='}))

proc newEditorRegistry*(fs: FsRuntimePort; path: string; random: RandomBytesFn;
                        now: ClockMsFn): Result[EditorRegistry, string] =
  ## A missing file is no editors; a broken one is an error, so it is never
  ## overwritten by an empty list.
  var text = ""
  if fs.entryKind(path) == fekFile:
    text = ? fs.readFile(path)
  let creds = ? decodeCredentials(text)
  ok(EditorRegistry(fs: fs, path: path, random: random, now: now, creds: creds))

proc save(r: EditorRegistry): Result[void, string] =
  let dir = r.path[0 ..< max(0, r.path.rfind('/'))]
  if dir.len > 0: ? r.fs.createDir(dir)
  r.fs.writePrivate(r.path, $encodeCredentials(r.creds))

proc refresh(r: EditorRegistry) =
  ## The file is the truth: `ctl editor revoke` writes it from another
  ## process. Unreadable, the last good list stays.
  var text = ""
  if r.fs.entryKind(r.path) == fekFile:
    text = r.fs.readFile(r.path).valueOr: return
  let creds = decodeCredentials(text).valueOr: return
  r.creds = creds

proc beginPairing*(r: EditorRegistry; name: string): Result[PairingStarted, string] =
  let secret = ? r.randomText(32)
  let codeBytes = ? r.random(6)
  let code = pairingCode(codeBytes)
  ? r.pairings.begin(secret, code, name, r.now())
  ok(PairingStarted(secret: secret, code: code))

proc confirmPairing*(r: EditorRegistry; code: string; userId: UserId): Result[string, string] =
  r.pairings.confirm(code, userId, r.now())

proc collectPairing*(r: EditorRegistry; secret: string): Result[PairingCollected, string] =
  ## On the confirmed poll the credential is minted, saved and handed over,
  ## once; a failed save hands nothing (the editor pairs again).
  let poll = r.pairings.collect(secret, r.now())
  if poll.state != epsConfirmed:
    return ok(PairingCollected(state: poll.state))
  let token = ? r.randomText(32)
  let id = "ed-" & (? r.randomText(6))
  r.refresh()
  r.creds.add newEditorCredential(token, id, poll.userId, poll.name, r.now())
  let saved = r.save()
  if saved.isErr:
    r.creds.setLen(r.creds.len - 1)
    return err(saved.error)
  ok(PairingCollected(state: epsConfirmed, token: token))

proc personFor*(r: EditorRegistry; token: string): Result[UserId, string] =
  r.refresh()
  r.creds.personFor(token)

func editors*(r: EditorRegistry): seq[EditorCredential] = r.creds

proc revokeEditor*(r: EditorRegistry; id: string): Result[void, string] =
  r.refresh()
  let before = r.creds
  ? r.creds.revoke(id)
  let saved = r.save()
  if saved.isErr:
    r.creds = before
    return err(saved.error)
  ok()

const EditorHelpText = "Para conectar um editor (Zed e outros com ACP), rode `donkey acp` nele " &
  "e mande aqui o código que ele mostrar: `/editor CÓDIGO`."

proc editorCommand*(r: EditorRegistry; userId: UserId; value: string): Result[string, string] =
  ## `/editor` (list), `/editor <code>` (confirm), `/editor revogar <id>`.
  r.refresh()
  let arg = value.strip
  if arg.len == 0:
    var lines: seq[string]
    for c in r.creds:
      if c.userId == userId: lines.add "- " & c.name & " (`" & c.id & "`)"
    if lines.len == 0:
      return ok("Nenhum editor conectado a você.\n\n" & EditorHelpText)
    return ok("Editores conectados a você:\n" & lines.join("\n") &
              "\n\nPara desconectar um: `/editor revogar <id>`.")
  let words = arg.splitWhitespace
  if words[0].toLowerAscii in ["revogar", "revoke"]:
    if words.len < 2: return err("Diga qual: `/editor revogar <id>`.")
    var found = -1
    for i, c in r.creds:
      if c.id == words[1] and c.userId == userId: found = i
    if found >= 0:
      ## Copies: revoking re-reads the file and replaces the list.
      let (id, name) = (r.creds[found].id, r.creds[found].name)
      ? r.revokeEditor(id)
      return ok("Editor " & name & " desconectado.")
    return err("Você não tem editor com esse id. Veja a lista com `/editor`.")
  let name = r.confirmPairing(arg, userId)
  if name.isErr:
    return err("Nenhum editor espera esse código (ou ele passou de 10 minutos). " & EditorHelpText)
  ok("Pronto: " & name.get & " agora conversa como você, com a sua memória. " &
     "Para ver ou desconectar: `/editor`.")

proc editorTable*(r: EditorRegistry): string =
  ## `donkey ctl editor list`: every paired editor, never a token.
  r.refresh()
  if r.creds.len == 0: return "No paired editors."
  result = "id\tuser\tname"
  for c in r.creds:
    result.add "\n" & c.id & "\t" & $c.userId & "\t" & c.name
