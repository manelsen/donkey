## TOML parsing callable from gcsafe code.
##
## parsetoml keeps no module-level state (no global `var`): every proc works
## on what it is given. It is just not annotated, so the compiler cannot see
## that. The single cast below says so once, instead of at every call site.

import parsetoml
export parsetoml

proc parseTomlString*(text: string): TomlValueRef {.gcsafe.} =
  ## gcsafe: parsetoml has no global state; it is only missing the annotation
  {.cast(gcsafe).}:
    result = parsetoml.parseString(text)

proc parseTomlFile*(path: string): TomlValueRef {.gcsafe.} =
  ## gcsafe: parsetoml has no global state; it is only missing the annotation
  {.cast(gcsafe).}:
    result = parsetoml.parseFile(path)
