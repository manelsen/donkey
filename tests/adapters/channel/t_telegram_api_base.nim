## Telegram API base override tests (Hugging Face proxy support).

import std/unittest
import donkey/adapters/channel/telegram

proc runTests*() =
  suite "telegram api base":

    test "defaults to the official Bot API":
      let adapter = newTelegramAdapter("token", "/tmp/donkey_telegram_identity.json")
      check adapter.apiBaseValue == TelegramApiBase

    test "uses an explicit proxy base":
      let adapter = newTelegramAdapter(
        "token", "/tmp/donkey_telegram_identity.json",
        apiBase = "https://proxy.example")
      check adapter.apiBaseValue == "https://proxy.example"

when isMainModule:
  runTests()
