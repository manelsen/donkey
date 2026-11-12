## dotenv — loads KEY=VALUE pairs from a .env file into the process environment.
##
## Format:
##   # comment
##   KEY=value
##   KEY="quoted value"
##   KEY=   (empty)
##
## Lines starting with # are ignored. Leading/trailing whitespace is stripped.
## Values can be quoted with single or double quotes.

import std/[os, strutils]

proc parseEnvFile*(path: string): seq[(string, string)] =
  ## Parses KEY=VALUE pairs without touching the process environment.
  ## Returns an empty seq if the file doesn't exist; read errors propagate.
  if not fileExists(path):
    return @[]

  for rawLine in lines(path):
    let line = rawLine.strip()
    if line.len == 0 or line[0] == '#':
      continue

    let eqIdx = line.find('=')
    if eqIdx < 0:
      continue

    let key = line[0 ..< eqIdx].strip()
    var value = line[eqIdx + 1 .. ^1].strip()

    # Unquote
    if value.len >= 2:
      if (value[0] == '"' and value[^1] == '"') or
         (value[0] == '\'' and value[^1] == '\''):
        value = value[1 ..< value.len - 1]

    if key.len > 0:
      result.add((key, value))

proc loadEnvFile*(path: string): int =
  ## Loads a .env file into the process environment.
  ## Returns the number of variables loaded.
  ## Silently returns 0 if the file doesn't exist.
  try:
    for (key, value) in parseEnvFile(path):
      # Don't override existing env vars (explicit env takes precedence)
      if getEnv(key).len == 0:
        putEnv(key, value)
        inc result
  except CatchableError:
    discard

proc envFilePath*(home: string): string =
  ## Returns the path to the donkey.env file.
  ## Checks: 1) {home}/donkey.env, 2) ~/.config/donkey/donkey.env
  let local = home / "donkey.env"
  if fileExists(local):
    return local
  getConfigDir() / "donkey" / "donkey.env"

proc loadDonkeyEnv*(home: string): int =
  ## Loads the donkey.env file for the given home directory.
  let path = envFilePath(home)
  loadEnvFile(path)
