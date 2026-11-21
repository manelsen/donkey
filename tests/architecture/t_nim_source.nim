## Reading Nim source for the architecture scans: `codeOnly` blanks comments
## and literals so a scan matches code, not text that merely looks like it.

import std/[strutils, unittest]

func isIdentChar*(c: char): bool = c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

func codeOnly*(src: string): string =
  ## `src` with comments and string/char literals blanked out, newlines kept,
  ## so "except:" in text is not mistaken for code and line numbers still
  ## match. Lexical state carries across lines: `#[ ]#` block comments (they
  ## nest), `"""` strings, raw strings (`r"…"`, `fmt"…"`, where `\` is not an
  ## escape and `""` is a quote), plain strings and char literals.
  var i = 0
  template blank(c: char) = result.add(if c == '\n': '\n' else: ' ')
  while i < src.len:
    let c = src[i]
    let prev = if i > 0: src[i - 1] else: ' '
    if c == '#' and (src.continuesWith("#[", i) or src.continuesWith("##[", i)):
      ## A doc block (`##[`) nests and closes only with `##[` / `]##`; a
      ## plain block with `#[` / `]#`.
      let doc = src.continuesWith("##[", i)
      let (open, close) = if doc: ("##[", "]##") else: ("#[", "]#")
      var depth = 0
      while i < src.len:
        if src.continuesWith(open, i):
          inc depth
          for _ in open: blank(src[i]); inc i
        elif src.continuesWith(close, i):
          dec depth
          for _ in close: blank(src[i]); inc i
          if depth == 0: break
        else:
          blank(src[i]); inc i
    elif c == '#':
      while i < src.len and src[i] != '\n':
        blank(src[i]); inc i
    elif src.continuesWith("\"\"\"", i):
      result.add "   "; i += 3
      while i < src.len and not src.continuesWith("\"\"\"", i):
        blank(src[i]); inc i
      while i < src.len and src[i] == '"':
        blank(src[i]); inc i
    elif c == '"' and isIdentChar(prev):
      blank(c); inc i
      while i < src.len and src[i] != '\n':
        if src[i] == '"':
          if i + 1 < src.len and src[i + 1] == '"':
            blank(src[i]); blank(src[i + 1]); i += 2
            continue
          break
        blank(src[i]); inc i
      if i < src.len and src[i] == '"':
        blank(src[i]); inc i
    elif c == '"' or (c == '\'' and not isIdentChar(prev)):
      blank(c); inc i
      while i < src.len and src[i] != c and src[i] != '\n':
        if src[i] == '\\' and i + 1 < src.len:
          blank(src[i]); inc i
        blank(src[i]); inc i
      if i < src.len and src[i] == c:
        blank(src[i]); inc i
    else:
      result.add c; inc i

proc runTests*() =
  suite "nim source lexer":
    test "comments and literals are blanked, code and line count are kept":
      check codeOnly("a # except:") == "a          "
      check codeOnly("send(\"#\").isOkOr: discard").endsWith(".isOkOr: discard")
      check "except" notin codeOnly("const a = \"\"\"\nexcept:\n\"\"\"")
      check "except" notin codeOnly("#[\nexcept:\n#[ nested ]#\nexcept:\n]#")
      check "except" in codeOnly("let x = (try: r\"C:\\\" except: \"\")")
      check "except" in codeOnly("let n = 0'i64\nexcept:")
      check "except" notin codeOnly("let c = '\"'\necho \"except:\"")
      check codeOnly("a\n# b\nc").count('\n') == 2
      check "isOkOr" in codeOnly("##[ opening: #[ ]##\nsend().isOkOr: discard")
      check "isOkOr" in codeOnly("##[ a ##[ nested ]## b ]##\nsend().isOkOr: discard")
      check "isOkOr" in codeOnly("#[ a ]## b\nsend().isOkOr: discard")

when isMainModule:
  runTests()
