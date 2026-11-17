## telegram_format.nim — Markdown to Telegram-compatible HTML conversion.
##
## Telegram HTML supports a limited subset:
## <b>bold</b>, <i>italic</i>, <u>underline</u>, <s>strikethrough</s>,
## <a href="...">links</a>, <code>inline code</code>, <pre>preformatted</pre>,
## <blockquote>blockquote</blockquote>
##
## This module converts common Markdown to these tags and escapes <, > and &.

import std/[strutils, unicode]
import ../domain/text_format

func sanitizeForTelegram*(text: string): string =
  ## Sanitizes text for Telegram API by ensuring valid UTF-8 encoding
  ## and removing invalid byte sequences that cause "strings must be encoded in UTF-8" errors.
  result = ""
  var i = 0
  while i < text.len:
    let c = ord(text[i])
    # Check for valid UTF-8 start byte
    if (c and 0x80) == 0:
      # ASCII character
      result.add(text[i])
      inc(i)
    elif (c and 0xE0) == 0xC0:
      # 2-byte sequence
      if i + 1 < text.len and (ord(text[i + 1]) and 0xC0) == 0x80:
        result.add(text[i .. i + 1])
        inc(i, 2)
      else:
        inc(i)  # Invalid sequence, skip
    elif (c and 0xF0) == 0xE0:
      # 3-byte sequence
      if i + 2 < text.len and (ord(text[i + 1]) and 0xC0) == 0x80 and (ord(text[i + 2]) and 0xC0) == 0x80:
        result.add(text[i .. i + 2])
        inc(i, 3)
      else:
        inc(i)  # Invalid sequence, skip
    elif (c and 0xF8) == 0xF0:
      # 4-byte sequence
      if i + 3 < text.len and (ord(text[i + 1]) and 0xC0) == 0x80 and (ord(text[i + 2]) and 0xC0) == 0x80 and (ord(text[i + 3]) and 0xC0) == 0x80:
        result.add(text[i .. i + 3])
        inc(i, 4)
      else:
        inc(i)  # Invalid sequence, skip
    else:
      inc(i)  # Invalid start byte, skip
  
  # Replace any remaining invalid characters (like replacement character)
  result = result.replace("\uFFFD", "")

func findUnescaped(md: string; needle: string; start: int): int =
  ## Finds `needle` skipping occurrences escaped with a backslash.
  var i = start
  while i < md.len:
    let at = md.find(needle, i)
    if at < 0:
      return -1
    var backslashes = 0
    var j = at - 1
    while j >= 0 and md[j] == '\\':
      inc backslashes
      dec j
    if backslashes mod 2 == 0:
      return at
    i = at + 1
  -1

func backtickRun(md: string; start: int): int =
  ## Length of the backtick run starting at `start`.
  while start + result < md.len and md[start + result] == '`':
    inc result

func findBacktickRun(md: string; start, runLen: int; exact = false): int =
  ## Index of the next backtick run of at least `runLen` (or exactly `runLen`
  ## when `exact`), or -1.
  var i = start
  while i < md.len:
    if md[i] == '`':
      let n = backtickRun(md, i)
      if (if exact: n == runLen else: n >= runLen):
        return i
      i += n
    else:
      inc i
  -1

func isFenceCloseLine(md: string; pos: int): bool =
  ## A closing fence sits at the start of a line and is followed only by
  ## spaces or tabs until the line ends.
  var j = pos
  while j < md.len and md[j] == '`': inc j
  while j < md.len and (md[j] == ' ' or md[j] == '\t'): inc j
  j >= md.len or md[j] == '\n' or md[j] == '\r'

func findFenceClose(md: string; start, runLen: int): int =
  var i = start
  while i < md.len:
    if md[i] == '`' and (i == 0 or md[i - 1] == '\n'):
      let n = backtickRun(md, i)
      if n >= runLen and isFenceCloseLine(md, i):
        return i
      i += n
    else:
      inc i
  -1

func markdownToTelegramHtml*(md: string): string =
  ## Robust Markdown -> Telegram HTML converter.
  ## Implementation logic inspired by nullclaw.
  var buf = ""
  var i = 0
  var lineStart = true

  while i < md.len:
    # ── Backslash escapes ──
    ## `\*` and friends render as the literal character, so dynamic values can
    ## be escaped before they are embedded in a formatted message.
    if md[i] == '\\' and i + 1 < md.len and md[i + 1] in MarkdownInlineSpecials:
      buf.add(escapeHtml($md[i + 1]))
      i += 2
      lineStart = false
      continue

    # ── Code fences and inline code ──
    ## A fence is a run of three or more backticks at the start of a line; its
    ## closing run must be at least as long, so inner ``` stays literal. CRLF
    ## is accepted and normalised. A run that is not at line start is inline
    ## code, not a fence.
    if md[i] == '`':
      let runLen = backtickRun(md, i)
      if runLen >= 3 and lineStart:
        var contentStart = i + runLen
        let langEnd = md.find('\n', contentStart)
        if langEnd >= 0:
          contentStart = langEnd + 1
        let close = findFenceClose(md, contentStart, runLen)
        if close >= 0:
          let content = md[contentStart ..< close].replace("\r\n", "\n")
          buf.add("<pre>")
          buf.add(escapeHtml(content))
          buf.add("</pre>")
          i = close + backtickRun(md, close)
          if i < md.len and md[i] == '\r': inc i
          if i < md.len and md[i] == '\n': inc i
          lineStart = true
          continue
      else:
        let close = findBacktickRun(md, i + runLen, runLen, exact = true)
        if close >= 0:
          buf.add("<code>")
          buf.add(escapeHtml(md[i + runLen ..< close]))
          buf.add("</code>")
          i = close + runLen
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
      let close = findUnescaped(md, "**", i + 2)
      if close >= 0:
        buf.add("<b>")
        buf.add(markdownToTelegramHtml(md[i + 2 ..< close]))
        buf.add("</b>")
        i = close + 2
        lineStart = false
        continue

    # ── Bold __text__ ──
    if i + 1 < md.len and md[i] == '_' and md[i + 1] == '_':
      let close = findUnescaped(md, "__", i + 2)
      if close >= 0:
        buf.add("<b>")
        buf.add(markdownToTelegramHtml(md[i + 2 ..< close]))
        buf.add("</b>")
        i = close + 2
        lineStart = false
        continue

    # ── Italic *text* ──
    if md[i] == '*' and (i == 0 or md[i - 1] in {' ', '\n', '('}):
      let close = findUnescaped(md, "*", i + 1)
      if close > i + 1:
        buf.add("<i>")
        buf.add(markdownToTelegramHtml(md[i + 1 ..< close]))
        buf.add("</i>")
        i = close + 1
        lineStart = false
        continue

    # ── Italic _text_ ──
    if md[i] == '_' and (i == 0 or md[i - 1] in {' ', '\n', '('}):
      let close = findUnescaped(md, "_", i + 1)
      if close > i + 1:
        buf.add("<i>")
        buf.add(markdownToTelegramHtml(md[i + 1 ..< close]))
        buf.add("</i>")
        i = close + 1
        lineStart = false
        continue

    # ── Strikethrough ~~text~~ ──
    if i + 1 < md.len and md[i] == '~' and md[i + 1] == '~':
      let close = findUnescaped(md, "~~", i + 2)
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

    # ── Tables | col | → clean text lines ──
    # Markdown tables: | A | B | \n |---|---|\n | 1 | 2 |
    # Telegram has no table HTML; strip syntax and format as clean text.
    if md[i] == '|':
      var tableLines: seq[string] = @[]
      var j = i
      var foundTable = false
      while j < md.len:
        let lineEnd = md.find('\n', j)
        let lineEndIdx = if lineEnd >= 0: lineEnd else: md.len
        let line = md[j ..< lineEndIdx].strip
        if line.len > 0 and line[0] == '|':
          foundTable = true
          let isSep = (let body = line[1 ..< line.len]; body.len > 0 and body.allCharsInSet({'-', '|', ' ', ':'}))
          if not isSep:
            var cells = line
            if cells[^1] == '|': cells = cells[0 ..< ^1]
            if cells.len > 0 and cells[0] == '|': cells = cells[1 ..< cells.len]
            let parts = cells.split('|')
            var cleanParts: seq[string]
            for p in parts:
              let stripped = p.strip
              if stripped.len > 0: cleanParts.add(stripped)
            tableLines.add(cleanParts.join(" • "))
        elif foundTable:
          break
        if lineEnd < 0:
          j = md.len
          break
        j = lineEnd + 1
      if foundTable and tableLines.len > 0:
        for t in tableLines:
          buf.add(t)
          buf.add('\n')
        i = j
        lineStart = true
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
