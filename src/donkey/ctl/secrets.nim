## ctl/secrets.nim — `donkey ctl secret` handlers.

import std/[os, sets, terminal]
import ../core/pipeops
import ../config/dotenv
import ../adapters/secrets/vault

# ── ctl secret commands ──────────────────────────────────────────────────────

proc ctlSecretSet*(vault: SecretVault; name: string): Result[void, string] =
  ## Reads one line from stdin without echo so the secret never appears in
  ## shell history or the process argument list.
  stderr.writeLine "Enter value for " & name & ":"
  var secret = ""
  try:
    secret = readPasswordFromStdin("")
  except CatchableError as e:
    return err("could not read secret from stdin: " & e.msg)
  let res = vault.setSecret(name, secret)
  if res.isErr:
    return err(res.error)
  echo "Stored secret " & name & "."
  ok()

proc ctlSecretList*(vault: SecretVault): Result[void, string] =
  let names = vault.listSecretNames()
  if names.isErr:
    return err(names.error)
  if names.get().len == 0:
    echo "No secrets stored."
    return ok()
  for name in names.get():
    echo name
  ok()

proc ctlSecretRemove*(vault: SecretVault; name: string): Result[void, string] =
  let res = vault.removeSecret(name)
  if res.isErr:
    return err(res.error)
  if not res.get():
    return err("secret not found: " & name)
  echo "Removed secret " & name & "."
  ok()

proc ctlSecretImportEnv*(vault: SecretVault;
                         path: string): Result[void, string] =
  if not fileExists(path):
    return err("env file not found: " & path)
  var entries: seq[(string, string)]
  try:
    entries = parseEnvFile(path)
  except CatchableError as e:
    return err("could not read " & path & ": " & e.msg)
  var prepared: seq[(string, string)]
  var seen = initHashSet[string]()
  var skipped: seq[string]
  for (name, value) in entries:
    ## loadEnvFile keeps the first occurrence; import must do the same.
    if value.len == 0 or name in seen:
      continue
    seen.incl(name)
    if name in BootstrapEnvVars:
      skipped.add(name)
      continue
    prepared.add((name, value))

  let imported = vault.setSecrets(prepared)
  if imported.isErr:
    return err("could not import " & path & ": " & imported.error)
  for name in skipped:
    echo "Skipped bootstrap variable " & name & " (keep it in donkey.env)."
  echo "Imported " & $imported.get() & " secret(s) from " & path & "."
  ok()
