## Pure URL validation and HTML conversion for web_fetch tool.
## No I/O - safe for use in adapters and domain logic.

import std/[strutils, parseutils, unicode]
import ../url_policy
export url_policy

func decodeHtmlEntities*(text: string): string =
  ## Decode common HTML entities.
  result = text
  result = result.replace("&amp;", "&")
  result = result.replace("&lt;", "<")
  result = result.replace("&gt;", ">")
  result = result.replace("&quot;", "\"")
  result = result.replace("&#39;", "'")
  result = result.replace("&apos;", "'")
  result = result.replace("&nbsp;", " ")
  result = result.replace("&#x27;", "'")
  result = result.replace("&#x2F;", "/")
  # Handle numeric entities
  var i = 0
  while i < result.len:
    if result[i] == '&' and i + 1 < result.len and result[i + 1] == '#':
      var j = i + 2
      var numStr = ""
      while j < result.len and result[j] in {'0'..'9', 'x', 'X'}:
        numStr.add(result[j])
        inc j
      if j < result.len and result[j] == ';':
        let isHex = numStr.startsWith('x') or numStr.startsWith('X')
        var num: int
        if isHex:
          discard parseHex(numStr[1 .. ^1], num)
        else:
          num = parseInt(numStr)
        if num > 0 and num <= 1114111:  # Valid Unicode range
          let ch = Rune(num).toUTF8
          result = result[0 ..< i] & ch & result[j + 1 .. ^1]
          i += ch.len - 1
        else:
          inc i
      else:
        inc i
    else:
      inc i

func stripHtmlTags*(html: string): string =
  ## Remove HTML tags from string.
  result = ""
  var inTag = false
  var inScript = false
  var inStyle = false
  var i = 0
  
  while i < html.len:
    let c = html[i]
    
    # Check for script/style tag boundaries
    if i + 7 <= html.len:
      let tag = html[i .. i + 7].toLowerAscii
      if tag == "<script":
        inScript = true
      elif tag == "</script":
        inScript = false
        i += 8
        continue
      elif tag == "<style":
        inStyle = true
      elif tag == "</style":
        inStyle = false
        i += 8
        continue
    
    if inScript or inStyle:
      inc i
      continue
    
    if c == '<':
      inTag = true
      inc i
      continue
    
    if c == '>':
      inTag = false
      inc i
      continue
    
    if not inTag:
      result.add(c)
    
    inc i

func normalizeWhitespace*(text: string): string =
  ## Collapse multiple spaces/newlines to single space, strip leading/trailing.
  result = ""
  var lastWasSpace = true  # Start true to strip leading
  for c in text:
    if c == ' ' or c == '\t' or c == '\n' or c == '\r':
      if not lastWasSpace:
        result.add(' ')
        lastWasSpace = true
    else:
      result.add(c)
      lastWasSpace = false
  # Strip trailing space
  if result.len > 0 and result[^1] == ' ':
    result.setLen(result.len - 1)

func convertBasicMarkdown*(text: string): string =
  ## Convert HTML-like formatting to Markdown.
  result = text
  
  # Bold: <b>...</b> or <strong>...</strong> -> **...**
  var i = 0
  result = ""
  i = 0
  while i < text.len:
    if text[i] == '<' and i + 3 < text.len:
      let tagLower = text[i .. i + 3].toLowerAscii
      if tagLower == "<b>" or tagLower == "<st":
        if tagLower == "<b>":
          result.add("**")
          i += 3
          continue
        elif i + 7 < text.len and text[i .. i + 7].toLowerAscii == "<strong>":
          result.add("**")
          i += 8
          continue
      elif text[i .. i + 4].toLowerAscii == "</b>":
        result.add("**")
        i += 4
        continue
      elif i + 8 < text.len and text[i .. i + 8].toLowerAscii == "</strong>":
        result.add("**")
        i += 9
        continue
    # Italic: <i>...</i> or <em>...</em> -> *...*
    if text[i] == '<' and i + 3 < text.len:
      let tagLower = text[i .. i + 3].toLowerAscii
      if tagLower == "<i>":
        result.add("*")
        i += 3
        continue
      elif i + 4 < text.len and text[i .. i + 4].toLowerAscii == "</i>":
        result.add("*")
        i += 5
        continue
      elif i + 3 < text.len and text[i .. i + 3].toLowerAscii == "<em":
        result.add("*")
        i += 4
        continue
      elif i + 4 < text.len and text[i .. i + 4].toLowerAscii == "</em>":
        result.add("*")
        i += 5
        continue
    # Code: <code>...</code> -> `...`
    if text[i] == '<' and i + 5 < text.len:
      let tagLower = text[i .. i + 5].toLowerAscii
      if tagLower == "<code":
        result.add("`")
        i += 5
        continue
      elif text[i .. i + 6].toLowerAscii == "</code>":
        result.add("`")
        i += 7
        continue
    # Links: <a href="...">text</a> -> [text](...)
    if text[i] == '<' and i + 2 < text.len and text[i .. i + 2].toLowerAscii == "<a":
      var j = i + 2
      var href = ""
      # Find href attribute
      while j < text.len and text[j] != '>':
        if j + 5 < text.len and text[j .. j + 5].toLowerAscii == "href=":
          j += 6
          let quote = if text[j] in {'"', '\''}: text[j] else: ' '
          if quote != ' ':
            inc j
            while j < text.len and text[j] != quote:
              href.add(text[j])
              inc j
            if j < text.len: inc j
          else:
            while j < text.len and text[j] notin {' ', '>', '\n', '\r'}:
              href.add(text[j])
              inc j
        else:
          inc j
      # Skip to close of opening tag
      while j < text.len and text[j] != '>':
        inc j
      if j < text.len: inc j
      result.add("[")
      i = j
      continue
    if text[i] == '<' and i + 3 < text.len and text[i .. i + 3].toLowerAscii == "</a":
      result.add("]")
      i += 4
      while i < text.len and text[i] != '>':
        inc i
      if i < text.len: inc i
      continue
    # <br> -> newline
    if text[i] == '<' and i + 3 < text.len:
      let tagLower = text[i .. i + 3].toLowerAscii
      if tagLower == "<br":
        result.add("\n")
        i += 4
        continue
    result.add(text[i])
    inc i

func htmlToText*(html: string; maxChars: int = 0): string =
  ## Convert HTML to clean text.
  ## Strips tags, decodes entities, collapses whitespace.
  ## If maxChars > 0, truncates with "..." marker.
  var text = html
  text = text.stripHtmlTags
  text = text.decodeHtmlEntities
  text = text.convertBasicMarkdown
  text = text.normalizeWhitespace
  if maxChars > 0 and text.len > maxChars:
    text = text[0 ..< maxChars] & "..."
  text
