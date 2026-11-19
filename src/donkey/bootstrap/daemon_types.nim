## daemon_types — shared daemon state and wiring value types.
##
## Composition-root code extracted from `src/donkey.nim`; it is not app logic
## and may reference concrete adapters.
##
## Extracted from the entry point so route metrics, gateway startup and
## daemon wiring can share one definition of the runtime state without
## importing `donkey.nim`.

import std/tables
import chronos/asyncsync
import donkey/adapters/memory/md_file
import donkey/adapters/state/runtime_store
import donkey/adapters/channel/telegram
import donkey/adapters/channel/discord
import donkey/adapters/channel/wecom
import donkey/adapters/channel/wechat
import donkey/adapters/channel/qq_channel
import donkey/adapters/channel/feishu
import donkey/adapters/channel/slack
import donkey/adapters/channel/dingtalk
import donkey/adapters/channel/line
import donkey/adapters/channel/matrix
import donkey/adapters/channel/email
import donkey/adapters/channel/whatsapp
import donkey/adapters/channel/cli_repl
import donkey/adapters/channel/signal
import donkey/adapters/tools/browser
import donkey/app/session_manager
import donkey/app/tool_loop_runtime
import donkey/core/outbound/outbound
import donkey/domain/channels/line_policy
import donkey/domain/message
import donkey/ports/memory
import donkey/ports/provider
import donkey/ports/runtime_state
import donkey/ports/tool

const
  RecentRouteSampleLimit* = 32
  DefaultRecentRouteSampleTtlSec* = 6 * 60 * 60
  DefaultProviderCooldownSec* = 10 * 60

type RouteSample* = object
  ok*: bool
  elapsedMs*: int
  recordedAtUnix*: int64

type DaemonToolBundle* = object
  clients*: seq[ToolRuntimePort]
  tools*:   seq[ToolDescription]
  browserRuntime*: BrowserToolRuntime

type GlobalProviderBundle* = object
  completeFn*: CompleteFn
  streamFn*:   StreamFn

type DaemonEnv* = object
  telegramToken*: string
  discordToken*:  string
  discordGuildId*: string
  wecomCorpId*:   string
  wechatAppId*:   string
  feishuAppId*:   string
  slackBotToken*: string
  slackAppToken*: string
  dingTalkAppKey*: string
  dingTalkAppSecret*: string
  dingTalkRobotCode*: string
  qqApiBase*:     string
  qqOfficialAppId*: string
  qqOfficialApiBase*: string
  memory*:        MdFileAdapter
  identityPath*:  string
  wecomAgentId*:  int
  whatsappAccessToken*: string
  whatsappPhoneNumberId*: string
  webhookPort*: int
  webhookHost*: string
  webhookTlsCert*: string
  webhookTlsKey*: string
  slackSigningSecret*: string
  feishuVerificationToken*: string
  feishuEncryptKey*: string
  lineChannelSecret*: string
  lineChannelAccessToken*: string
  lineAllowedGroups*: seq[string]
  lineAllowedUsers*: seq[string]
  matrixWebhookToken*: string
  whatsappVerifyToken*: string
  whatsappAppSecret*: string

type DaemonAdapters* = object
  tg*: TelegramAdapter
  dc*: DiscordAdapter
  wc*: WeComAdapter
  wch*: WeChatAdapter
  qq*: QQChannelAdapter
  fs*: FeishuAdapter
  sl*: SlackAdapter
  dt*: DingTalkAdapter
  ln*: LineAdapter
  mx*: MatrixAdapter
  em*: EmailAdapter
  wa*: WhatsAppAdapter
  cli*: CliAdapter
  signal*: SignalAdapter

type DaemonServices* = object
  toolClients*:      seq[ToolRuntimePort]
  tools*:            seq[ToolDescription]
  browserRuntime*:   BrowserToolRuntime
  globalCompleteFn*: CompleteFn
  globalStreamFn*:   StreamFn
  tgTypingFn*:       TypingFn
  globalSearchFn*:   SearchFn

type DaemonRuntime* = ref object
  globalOutbox*:         AsyncQueue[OutboundMessage]
  sm*:                   SessionManager
  stateStore*:           RuntimeStateStore
  ledger*:               DeliveryLedgerPort
  ledgerWorker*:         LedgerCompactionWorker
  presentationState*:    PresentationState
  routeCounts*:          Table[string, int]
  routeCallCounts*:      Table[string, int]
  routeOkCounts*:        Table[string, int]
  routeErrCounts*:       Table[string, int]
  routeLatencyTotalsMs*: Table[string, int64]
  routeRecentSamples*:   Table[string, seq[RouteSample]]
  providerCooldownUntil*: Table[string, int64]
  routeHealthPath*:      string
  lastReminderCheckMs*:  int64
  lastEmailPollMs*:      int64
  lastSignalPollMs*:     int64
  lineReplay*:           LineReplayCache
  msgSeq*:               int
  daemonStartMs*:        int64

type DaemonContext* = ref object
  env*:      DaemonEnv
  adapters*: DaemonAdapters
  services*: DaemonServices
  runtime*:  DaemonRuntime

type DaemonTickResult* = object
  ok*:               bool
  remindersChecked*: bool

type DaemonLoopResult* = object
  sleepMs*: int

type DaemonBootstrap* = object
  memory*: MdFileAdapter
  ctx*:    DaemonContext
