## telegram_format.nim — Markdown to Telegram-compatible HTML conversion.
##
## Telegram HTML supports a limited subset:
## <b>bold</b>, <i>italic</i>, <u>underline</u>, <s>strikethrough</s>,
## <a href="...">links</a>, <code>inline code</code>, <pre>preformatted</pre>,
## <blockquote>blockquote</blockquote>
##
## This module converts common Markdown to these tags and escapes <, > and &.

import std/[strutils, options]

func escapeHtml*(text: string): string =
  ## Escapes <, > and & for Telegram HTML.
  result = text.replace("&", "&amp;")
               .replace("<", "&lt;")
               .replace(">", "&gt;")

func findTripleBacktick(md: string, start: int): Option[int] =
  let idx = md.find("```", start)
  if idx >= 0: some(idx) else: none(int)

func markdownToTelegramHtml*(md: string): string =
  ## Robust Markdown -> Telegram HTML converter.
  ## Implementation logic inspired by nullclaw.
  var buf = ""
  var i = 0
  var lineStart = true

  while i < md.len:
    # ── Code blocks ``` ... ``` ──
    if i + 2 < md.len and md[i] == '`' and md[i + 1] == '`' and md[i + 2] == '`':
      let contentStart = if i + 3 < md.len and md[i + 3] == '\n': i + 4 else: i + 3
      let langEnd = md.find('\n', i + 3)
      let actualStart = if langEnd >= 0 and langEnd < md.len: langEnd + 1 else: contentStart
      
      let close = findTripleBacktick(md, actualStart)
      if close.isSome:
        let endIdx = close.get()
        buf.add("<pre>")
        buf.add(escapeHtml(md[actualStart ..< endIdx]))
        buf.add("</pre>")
        i = endIdx + 3
        if i < md.len and md[i] == '\n': i += 1
        lineStart = true
        continue

    # ── Inline code `...` ──
    if md[i] == '`':
      let close = md.find('`', i + 1)
      if close >= 0:
        buf.add("<code>")
        buf.add(escapeHtml(md[i + 1 ..< close]))
        buf.add("</code>")
        i = close + 1
        lineStart = false
        continue

    # ── Headers at line start ──
    if lineStart and md[i] == '#':
      var level = 0
      while i + level < md.len and md[i + level] == '#': level += 1
      if level >= 1 and level <= 6 and i + level < md.len and md[i + level] == ' ':
        i += level + 1 # skip "### "
        var endIdx = md.find('\n', i)
        if endIdx < 0: endIdx = md.len
        buf.add("<b>")
        buf.add(markdownToTelegramHtml(md[i ..< endIdx]))
        buf.add("</b>")
        i = endIdx
        lineStart = true
        continue

    # ── Blockquotes > text ──
    if lineStart and md[i] == '>':
      buf.add("<blockquote>")
      while i < md.len and md[i] == '>':
        var endIdx = md.find('\n', i)
        if endIdx < 0: endIdx = md.len
        
        let contentStart = if i + 1 < md.len and md[i + 1] == ' ': i + 2 else: i + 1
        let lineContent = md[contentStart ..< endIdx]
        
        buf.add(markdownToTelegramHtml(lineContent))
        
        i = endIdx
        if i < md.len:
          # Check if next line is also a blockquote
          if i + 1 < md.len and md[i + 1] == '>':
            buf.add('\n')
            i += 1
          else:
            # End of blockquote
            break
        else:
          break
      buf.add("</blockquote>")
      lineStart = true
      continue

    # ── Bold **text** ──
    if i + 1 < md.len and md[i] == '*' and md[i + 1] == '*':
      let close = md.find("**", i + 2)
      if close >= 0:
        buf.add("<b>")
        buf.add(markdownToTelegramHtml(md[i + 2 ..< close]))
        buf.add("</b>")
        i = close + 2
        lineStart = false
        continue

    # ── Bold __text__ ──
    if i + 1 < md.len and md[i] == '_' and md[i + 1] == '_':
      let close = md.find("__", i + 2)
      if close >= 0:
        buf.add("<b>")
        buf.add(markdownToTelegramHtml(md[i + 2 ..< close]))
        buf.add("</b>")
        i = close + 2
        lineStart = false
        continue

    # ── Italic *text* ──
    if md[i] == '*' and (i == 0 or md[i - 1] in {' ', '\n', '('}):
      let close = md.find('*', i + 1)
      if close > i + 1:
        buf.add("<i>")
        buf.add(markdownToTelegramHtml(md[i + 1 ..< close]))
        buf.add("</i>")
        i = close + 1
        lineStart = false
        continue

    # ── Italic _text_ ──
    if md[i] == '_' and (i == 0 or md[i - 1] in {' ', '\n', '('}):
      let close = md.find('_', i + 1)
      if close > i + 1:
        buf.add("<i>")
        buf.add(markdownToTelegramHtml(md[i + 1 ..< close]))
        buf.add("</i>")
        i = close + 1
        lineStart = false
        continue

    # ── Strikethrough ~~text~~ ──
    if i + 1 < md.len and md[i] == '~' and md[i + 1] == '~':
      let close = md.find("~~", i + 2)
      if close >= 0:
        buf.add("<s>")
        buf.add(markdownToTelegramHtml(md[i + 2 ..< close]))
        buf.add("</s>")
        i = close + 2
        lineStart = false
        continue

    # ── Links [text](url) ──
    if md[i] == '[':
      let closeBracket = md.find(']', i + 1)
      if closeBracket >= 0 and closeBracket + 1 < md.len and md[closeBracket + 1] == '(':
        let closeParen = md.find(')', closeBracket + 2)
        if closeParen >= 0:
          let text = md[i + 1 ..< closeBracket]
          let url = md[closeBracket + 2 ..< closeParen]
          buf.add("<a href=\"")
          buf.add(escapeHtml(url))
          buf.add("\">")
          buf.add(escapeHtml(text))
          buf.add("</a>")
          i = closeParen + 1
          lineStart = false
          continue

    # ── Normal character ──
    if md[i] == '\n':
      buf.add('\n')
      lineStart = true
    else:
      case md[i]
      of '&': buf.add("&amp;")
      of '<': buf.add("&lt;")
      of '>': buf.add("&gt;")
      else: buf.add(md[i])
      lineStart = false
    i += 1

  result = buf
