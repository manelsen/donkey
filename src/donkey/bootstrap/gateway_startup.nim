## gateway_startup — optional inbound gateway/webhook startup for the daemon.
##
## Composition-root code extracted from `src/donkey.nim`; it is not app logic
## and may reference concrete adapters.
##
## Each proc is a no-op when its channel credentials are absent, so the daemon
## can start every transport unconditionally.

import std/[net, os, strutils]
import donkey/core/log
import donkey/core/pipeops
import donkey/ports/http
import donkey/adapters/channel/discord
import donkey/adapters/channel/wecom
import donkey/adapters/channel/wechat
import donkey/adapters/channel/feishu
import donkey/adapters/channel/slack
import donkey/adapters/channel/slack_socket
import donkey/adapters/channel/dingtalk
import donkey/adapters/channel/matrix
import donkey/adapters/channel/whatsapp
import donkey/adapters/channel/qq_channel
import donkey/adapters/webhook/webhook_receiver
import ./daemon_types

proc startOptionalDiscordGateway*(dcAdapter: var DiscordAdapter;
                                  discordToken: string;
                                  discordGuildId: string;
                                  log: Logger) =
  if discordToken.len == 0:
    log.info("DISCORD_BOT_TOKEN not set — Discord disabled")
    return

  log.info("Discord gateway starting (token len=" & $discordToken.len & ")")
  dcAdapter.startGateway(log)
  let appId = dcAdapter.getAppId().valueOr:
    log.warn("Discord getAppId failed: " & error); ""
  if appId.len > 0:
    log.info("Discord appId: " & appId)
    ## Register globally (DM support via integration_types=[0,1] + contexts=[0,1,2])
    dcAdapter.registerSlashCommands(appId, guildId = "").isOkOr:
      log.warn("Discord slash cmd reg (global) failed: " & error)
    ## Also register guild commands when DISCORD_GUILD_ID is set — takes effect immediately
    if discordGuildId.len > 0:
      dcAdapter.registerSlashCommands(appId, guildId = discordGuildId).isOkOr:
        log.warn("Discord slash cmd reg (guild) failed: " & error)
      log.info("Discord slash commands registered (global + guild " & discordGuildId & ")")
    else:
      log.info("Discord slash commands registered (global)")
  else:
    log.warn("Discord slash commands NOT registered — appId unavailable")
  log.info("Discord gateway thread started")

proc startOptionalWeComGateway*(wcAdapter: var WeComAdapter;
                                wecomCorpId: string;
                                log: Logger) =
  if wecomCorpId.len == 0:
    log.info("WECOM_CORP_ID not set — WeCom disabled")
    return

  let wcPort = Port(parseInt(if getEnv("WECOM_WEBHOOK_PORT").len > 0:
                               getEnv("WECOM_WEBHOOK_PORT") else: "8081"))
  wcAdapter.startWebhook(wcPort, log)
  log.info("WeCom webhook started on port " & $wcPort)

proc startOptionalFeishuGateway*(fsAdapter: var FeishuAdapter;
                                 feishuAppId: string;
                                 log: Logger) =
  if feishuAppId.len == 0:
    log.info("FEISHU_APP_ID not set — Feishu disabled")
    return

  fsAdapter.startGateway()
  log.info("Feishu WebSocket gateway started")

proc startOptionalWeChatGateway*(wchAdapter: var WeChatAdapter;
                                 wechatAppId: string;
                                 log: Logger) =
  if wechatAppId.len == 0:
    log.info("WECHAT_APP_ID not set — WeChat disabled")
    return

  let port = Port(parseInt(if getEnv("WECHAT_WEBHOOK_PORT").len > 0:
                             getEnv("WECHAT_WEBHOOK_PORT") else: "8081"))
  wchAdapter.startWebhook(port, log)
  log.info("WeChat webhook listener started on port " & $port)

proc startOptionalSlackGateway*(slAdapter: var SlackAdapter;
                                slackBotToken: string;
                                slackAppToken: string;
                                slackHttp: HttpRuntimePort;
                                log: Logger) =
  if slackBotToken.len == 0:
    log.info("SLACK_BOT_TOKEN not set — Slack disabled")
    return

  slAdapter.openQueue()
  if slackAppToken.len > 0:
    startSlackSocketMode(slackAppToken, slackHttp, log).isOkOr:
      log.error("slack socket: " & error)
  elif getEnv("SLACK_SIGNING_SECRET").len == 0:
    log.warn("SLACK_SIGNING_SECRET/SLACK_APP_TOKEN not set — Slack inbound disabled")
  log.info("Slack gateway started")

proc startOptionalDingTalkGateway*(dtAdapter: var DingTalkAdapter;
                                   dingTalkAppKey: string;
                                   log: Logger) =
  if dingTalkAppKey.len == 0:
    log.info("DINGTALK_APP_KEY not set — DingTalk disabled")
    return

  dtAdapter.openQueue()
  log.info("DingTalk gateway started")

func matrixConfigured*(): bool =
  getEnv("MATRIX_HOMESERVER").len > 0 and
    getEnv("MATRIX_BOT_USER_ID").len > 0 and
    getEnv("MATRIX_ACCESS_TOKEN").len > 0

proc startOptionalMatrixGateway*(mxAdapter: var MatrixAdapter;
                                 log: Logger) =
  if not matrixConfigured():
    log.info("MATRIX_HOMESERVER/MATRIX_BOT_USER_ID/MATRIX_ACCESS_TOKEN not set — Matrix disabled")
    return

  mxAdapter.startGateway()
  log.info("Matrix gateway started")

proc startOptionalWhatsAppGateway*(waAdapter: var WhatsAppAdapter;
                                   accessToken: string;
                                   phoneNumberId: string;
                                   log: Logger) =
  if accessToken.len == 0 or phoneNumberId.len == 0:
    log.info("WHATSAPP_ACCESS_TOKEN/WHATSAPP_PHONE_NUMBER_ID not set — WhatsApp disabled")
    return

  waAdapter.openQueue()
  log.info("WhatsApp webhook queue started")

proc startOptionalWebhookReceiver*(env: DaemonEnv; log: Logger) =
  ## Mounts only the routes whose channel is configured AND has a secret.
  if env.webhookPort <= 0:
    log.info("DONKEY_WEBHOOK_PORT not set — webhook receiver disabled")
    return
  if (env.webhookTlsCert.len > 0) != (env.webhookTlsKey.len > 0):
    log.error("DONKEY_WEBHOOK_TLS_CERT and DONKEY_WEBHOOK_TLS_KEY must be set together — webhook receiver disabled")
    return

  let cfg = WebhookConfig(
    ## Slack events are drained by slack_runtime; only accept them when the
    ## bot token and signature secret are configured.
    slackSigningSecret:
      if env.slackBotToken.len > 0: env.slackSigningSecret else: "",
    feishuVerificationToken:
      if env.feishuAppId.len > 0: env.feishuVerificationToken else: "",
    feishuEncryptKey:
      if env.feishuAppId.len > 0: env.feishuEncryptKey else: "",
    dingtalkAppSecret:
      if env.dingTalkAppKey.len > 0: env.dingTalkAppSecret else: "",
    lineChannelSecret:
      if env.lineChannelAccessToken.len > 0: env.lineChannelSecret else: "",
    lineChannelAccessToken: env.lineChannelAccessToken,
    lineAllowedGroups: env.lineAllowedGroups,
    lineAllowedUsers: env.lineAllowedUsers,
    matrixToken:
      if matrixConfigured(): env.matrixWebhookToken else: "",
    whatsappVerifyToken:
      if env.whatsappAccessToken.len > 0 and env.whatsappPhoneNumberId.len > 0:
        env.whatsappVerifyToken
      else: "",
    whatsappAppSecret:
      if env.whatsappVerifyToken.len > 0: env.whatsappAppSecret else: "",
    tlsCertFile: env.webhookTlsCert,
    tlsKeyFile: env.webhookTlsKey,
  )
  startWebhookReceiver(cfg, env.webhookPort, env.webhookHost, log).isOkOr:
    log.error("webhook receiver: " & error)
    return
  let scheme = if env.webhookTlsCert.len > 0: "https" else: "http"
  log.info("webhook receiver started on " & scheme & "://" &
           env.webhookHost & ":" & $env.webhookPort)

proc startOptionalQQGateway*(qqAdapter: var QQChannelAdapter;
                             log: Logger) =
  if not qqAdapter.enabled():
    log.info("QQ not configured — QQ disabled")
    return
  case qqAdapter.kind
  of qbkOneBot:
    let oneBotPort = Port(parseInt(
      if getEnv("QQ_ONEBOT_WEBHOOK_PORT").len > 0:
        getEnv("QQ_ONEBOT_WEBHOOK_PORT") else: "8082"))
    qqAdapter.startWebhook(oneBotPort, log)
    log.info("QQ OneBot webhook listener started on port " & $oneBotPort)
  of qbkOfficial:
    log.info("QQ official API client enabled")
    qqAdapter.startGateway()
    log.info("QQ official gateway started")
  of qbkNone:
    discard
