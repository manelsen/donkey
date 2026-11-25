## reply_context_pure — what a reply is replying to, for the agent.
##
## When the person replies to an earlier message (Telegram's
## reply_to_message, Discord's referenced message, WhatsApp's context id),
## the channel gives the quoted text and the agent reads it before the
## message: "[Replying to: "…"]". One line, clipped, never mid-character.
## No quote, no prefix.

import std/[strutils, unicode]

const MaxQuotedChars* = 300

func oneLine(text: string): string =
  ## Whitespace runs (newlines included) become one space.
  var pendingSpace = false
  for r in text.strip.runes:
    if r.isWhiteSpace:
      pendingSpace = true
    else:
      if pendingSpace and result.len > 0:
        result.add ' '
      pendingSpace = false
      result.add $r

func clipped(text: string; maxBytes: int): string =
  if text.len <= maxBytes:
    return text
  var cut = maxBytes
  while cut > 0 and (ord(text[cut]) and 0xC0) == 0x80:
    dec cut
  text[0 ..< cut] & "…"

func withReplyContext*(text, quotedText: string): string =
  let quote = oneLine(quotedText)
  if quote.len == 0:
    return text
  "[Replying to: \"" & clipped(quote, MaxQuotedChars) & "\"]\n" & text
