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
const MarkdownInlineSpecials* = {'\\', '`', '*', '_', '~', '[', ']', '(', ')', '#', '>', '|'}

func escapeMarkdownInline*(text: string): string =
  ## Behavior derived from hermes-agent (MIT) fix a694040520; see
  ## docs/hermes-mining/telegram/CASES.md#tg-037
  ##
  ## Dynamic values (tool names, arguments, ids) are inserted into Markdown
  ## messages. A stray backtick or asterisk would open a span and swallow the
  ## rest of the message, so every markup character is escaped.
  for ch in text:
    if ch in MarkdownInlineSpecials:
      result.add('\\')
    result.add(ch)

func codeSpanText*(text: string): string =
  ## Behavior derived from hermes-agent (MIT) fix a694040520; see
  ## docs/hermes-mining/telegram/CASES.md#tg-037
  ##
  ## Inside a code span a backslash is not an escape, so escaping would show
  ## the backslash. Backticks are replaced instead, keeping the value readable
  ## and the span closed.
  for ch in text:
    result.add(if ch == '`': '\'' else: ch)
