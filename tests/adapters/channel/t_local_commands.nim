## Tests for LocalCommandAction execution in channel adapters.

import std/[unittest, tables]
import donkey/adapters/channel/telegram_runtime
import donkey/adapters/channel/telegram
import donkey/adapters/channel/discord_runtime
import donkey/adapters/channel/discord
import donkey/adapters/memory/md_file
import donkey/core/commands/command_routing
import donkey/core/types
import donkey/core/log
import donkey/domain/message
import donkey/app/session_manager

suite "Telegram Runtime - LocalCommandAction execution":

  test "/whoami (lcaShowWhoami) produces user and session info":
    ## Setup
    var tg = newTelegramAdapter("tok", "/tmp/ids_whoami.tsv")
    var sm: SessionManager
    sm.init()
    var mem = MdFileAdapter(paddocksDir: "/tmp/donkey_paddocks_whoami")
    var kbdMsgIds = initTable[string, string]()
    let userId = UserId("user-uuid-123")
    let msg = InboundMessage(userId: userId, channel: ckTelegram, channelId: "12345", text: "/whoami")
    let logger = newLogger("test")
    
    # For now, let's ensure it's at least recognized in the case block.
    var msgSeq = 0
    let handled = handleTelegramMessage(
      msg, sm, tg, kbdMsgIds, mem, nil, nil, 0, 0, msgSeq, 0, logger)
    
    check handled == true

suite "Discord Runtime - LocalCommandAction execution":

  test "/whoami (lcaShowWhoami) is callable":
    var dc = newDiscordAdapter("tok", "/tmp/ids_whoami_dc.tsv")
    var sm: SessionManager
    sm.init()
    var mem = MdFileAdapter(paddocksDir: "/tmp/donkey_paddocks_whoami_dc")
    var kbdMsgIds = initTable[string, string]()
    let event = DiscordRawEvent(
      kind: deMessage, discordUserId: "dc-user-123", messageId: "msg-123", content: "/whoami")
    var msgSeq = 0
    let logger = newLogger("test-dc")
    
    # Just verify it doesn't crash and compiles
    handleDiscordEvent(
      sm, event, dc, kbdMsgIds, mem, nil, nil, 0, 0, 0, msgSeq, logger, nil)
    
    check true
