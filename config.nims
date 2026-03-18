# Makes `src/` visible to all nim compilations in this project,
# including testament test files in tests/.
switch("path", "src")

# Required for httpclient HTTPS (Telegram API, Zhipu API).
switch("define", "ssl")

# Required for Discord gateway thread (Channel[T] cross-thread communication).
switch("threads", "on")

# Nimble package paths (chronos, parsetoml, results, nimcrypto).
import std/os
let nimblePkgs = getHomeDir() / ".nimble" / "pkgs2"
for kind, path in walkDir(nimblePkgs):
  if kind == pcDir:
    switch("path", path)
