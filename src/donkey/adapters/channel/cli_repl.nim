## CliAdapter — ChannelPort for local terminal REPL.
##
## receive() reads lines from stdin and returns them as InboundMessage.
## send() writes text to stdout.
## ack() is a no-op.
##
## This is a single-user local adapter: the user identity is fixed
## (local:cli) and messages are numbered sequentially.

import ../../core/types
import ../../core/pipeops
import ../../domain/message

const
  CliMaxCols* = 10_000  ## max line length before splitting

# ── CliAdapter ─────────────────────────────────────────────────────────────────

type
  CliAdapter* = object
    ## Local CLI REPL adapter.
    userId*:    UserId      ## fixed local user id ("local:cli")
    counter*:   int         ## running message id counter

const
  CliDefaultUserId* = UserId("local:cli")

# ── ChannelPort implementation ─────────────────────────────────────────────────

proc receive*(a: var CliAdapter): Result[seq[InboundMessage], string] =
  ## Reads one line from stdin, returns it as an InboundMessage.
  ## Returns err on EOF or read error.
  let line = stdin.readLine()
  if line.len == 0:
    return err("CliAdapter.receive: EOF")
  a.counter += 1
  let channelId = $a.counter
  let msg = InboundMessage(
    userId:    a.userId,
    channelId: channelId,
    text:      line,
    mediaUrl:  "",
    channel:   ckCli,
  )
  ok(@[msg])

proc send*(a: CliAdapter; msg: OutboundMessage): Result[void, string] =
  ## Writes message text to stdout. Splits at newlines to preserve formatting.
  if msg.text.len == 0:
    return ok()
  for chunk in splitChunks(msg.text, CliMaxCols):
    echo chunk
  ok()

proc sendReturnId*(a: CliAdapter; msg: OutboundMessage): Result[string, string] =
  ## Sends the message and returns "1" as a placeholder stream id.
  ? a.send(msg)
  ok("1")

proc editMessage*(a: CliAdapter; userId: UserId;
                  msgId, text: string): Result[void, string] =
  ## CLI does not support message editing. Returns ok silently.
  discard userId
  discard msgId
  discard text
  ok()

proc ack*(a: CliAdapter; channelId: string) =
  ## No-op for CLI.
  discard

# ── Constructor ───────────────────────────────────────────────────────────────

proc newCliAdapter*(userId = CliDefaultUserId): CliAdapter =
  CliAdapter(userId: userId, counter: 0)

# ── pure helpers ──────────────────────────────────────────────────────────────

func isCommand*(text: string): bool =
  ## Returns true if text starts with '/' (slash command).
  text.len > 0 and text[0] == '/'

func stripCommand*(text: string): string =
  ## Strips the leading '/' from a command, or returns text unchanged.
  if text.len > 0 and text[0] == '/':
    text[1 .. ^1]
  else:
    text
