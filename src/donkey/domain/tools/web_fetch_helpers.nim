## Pure URL validation and HTML conversion for web_fetch tool.
## No I/O - safe for use in adapters and domain logic.

import std/[strutils, parseutils, unicode]

func extractUrlHost*(rawUrl: string): string =
  ## Extract host from URL string.
  ## Returns empty string if URL is invalid or cannot parse.
  if rawUrl.len == 0:
    return ""
  
  # Strip protocol prefix
  var withoutProtocol = rawUrl
  for prefix in ["https://", "http://"]:
    if withoutProtocol.toLowerAscii.startsWith(prefix):
      withoutProtocol = withoutProtocol[prefix.len .. ^1]
      break
  
  # Extract host (everything before the first / or :)
  let slashIdx = withoutProtocol.find('/')
  let colonIdx = withoutProtocol.find(':')
  
  var hostEnd: int
  if slashIdx < 0 and colonIdx < 0:
    hostEnd = withoutProtocol.len
  elif slashIdx < 0:
    hostEnd = colonIdx
  elif colonIdx < 0:
    hostEnd = slashIdx
  else:
    hostEnd = min(slashIdx, colonIdx)
  
  if hostEnd <= 0:
    return ""
  
  withoutProtocol[0 ..< hostEnd]

func isPrivateUrl*(rawUrl: string): bool =
  ## Returns true when URL points to private/internal host.
  ## Checks: localhost, 127.x, 10.x, 192.168.x, 169.254.x, 172.16-31.x
  let host = extractUrlHost(rawUrl).toLowerAscii
  if host.len == 0:
    return false
  
  # localhost
  if host == "localhost" or host == "localhost.localdomain":
    return true
  
  # 127.x.x.x
  if host.startsWith("127."):
    return true
  
  # 10.x.x.x
  if host.startsWith("10."):
    return true
  
  # 192.168.x.x
  if host.startsWith("192.168."):
    return true
  
  # 169.254.x.x (link-local)
  if host.startsWith("169.254."):
    return true
  
  # 172.16-31.x.x
  if host.startsWith("172."):
    let parts = host[4 .. ^1].split('.')
    if parts.len >= 1 and parts[0].len > 0 and
       parts[0].allCharsInSet({'0'..'9'}):
      try:
        let first = parseInt(parts[0])
        if first >= 16 and first <= 31:
          return true
      except ValueError:
        discard  # overflow/non-numeric label: not an IPv4 literal
  
  # Check for IPv6 loopback and unique local addresses
  if host == "::1" or host.startsWith("fc") or host.startsWith("fd") or host.startsWith("fe80"):
    return true
  
  false

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
