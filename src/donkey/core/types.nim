## Core types — no external imports, all func.
## Everything else in the project builds on these.

type
  UserId*    = distinct string
  SessionId* = distinct string

  ChannelKind* = enum
    ## Identifies which messaging channel a message arrived on / should be sent to.
    ckTelegram, ckDiscord, ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp,
    ckSignal, ckDingTalk, ckMatrix, ckEmail, ckCli

  LogLevel* = enum
    lvlDebug, lvlInfo, lvlWarn, lvlError, lvlFatal

# ── LogLevel helpers ──────────────────────────────────────────────────────────

func `$`*(l: LogLevel): string =
  case l
  of lvlDebug: "debug"
  of lvlInfo:  "info"
  of lvlWarn:  "warn"
  of lvlError: "error"
  of lvlFatal: "fatal"

func parseLogLevel*(s: string): LogLevel =
  ## Unknown strings default to info (never crash on bad config).
  case s
  of "debug": lvlDebug
  of "warn":  lvlWarn
  of "error": lvlError
  of "fatal": lvlFatal
  else:       lvlInfo

# ── UserId / SessionId helpers ────────────────────────────────────────────────

func `$`*(id: UserId): string    {.borrow.}
func `==`*(a, b: UserId): bool   {.borrow.}
func `$`*(id: SessionId): string  {.borrow.}
func `==`*(a, b: SessionId): bool {.borrow.}

func `$`*(k: ChannelKind): string =
  case k
  of ckTelegram: "telegram"
  of ckDiscord:  "discord"
  of ckWeCom:    "wecom"
  of ckWeChat:   "wechat"
  of ckQQ:       "qq"
  of ckFeishu:   "feishu"
  of ckSlack:      "slack"
  of ckWhatsApp:   "whatsapp"
  of ckSignal:     "signal"
  of ckDingTalk:   "dingtalk"
  of ckMatrix:     "matrix"
  of ckEmail:      "email"
  of ckCli:        "cli"
