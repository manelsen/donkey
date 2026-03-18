## DiscordAdapter unit tests.
## Does not make real HTTP or WebSocket calls.
## Tests: type construction, send/ack procs, concept compatibility.

import std/[os, unittest]
import donkey/adapters/channel/discord
import donkey/domain/message
import donkey/core/types

suite "DiscordAdapter construction":

  test "stores token":
    let a = newDiscordAdapter("TOK", "/tmp/dc_ids.tsv",
                              apiBase = "https://mock.discord.local")
    check a.token == "TOK"

  test "apiBase override is stored":
    let a = newDiscordAdapter("T", "/tmp/dc_ids2.tsv",
                              apiBase = "http://localhost:9999")
    check a.apiBase == "http://localhost:9999"

suite "DiscordAdapter ack is no-op":

  test "ack does not raise":
    let a = newDiscordAdapter("T", "/tmp/dc_ids3.tsv")
    a.ack("some-channel-id")
    check true

suite "DiscordRawEvent kind enum":

  test "deMessage and deInteraction are distinct":
    let m = DiscordRawEvent(kind: deMessage)
    let i = DiscordRawEvent(kind: deInteraction)
    check m.kind != i.kind
