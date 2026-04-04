## text_format.nim — generic text sanitization and formatting helpers.
##
## No I/O, no side effects. All functions are `func`.
## Usable by any adapter or domain code that needs safe text output.

import std/strutils

func escapeHtml*(text: string): string =
  ## Escapes <, > and & for HTML-compatible output.
  ## Use this before inserting user text into any HTML/XML context.
  result = text.replace("&", "&amp;")
               .replace("<", "&lt;")
               .replace(">", "&gt;")