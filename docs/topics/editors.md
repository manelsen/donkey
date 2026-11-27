# Editors
Donkey inside Zed and other editors that speak the Agent Client Protocol.

## Overview

`donkey acp` puts Donkey in an editor's agent panel. The editor starts it as
a subprocess and talks to it with the [Agent Client
Protocol](https://agentclientprotocol.com) (ACP v1, JSON-RPC on stdin and
stdout). `donkey acp` relays each prompt to the daemon and streams the answer
back: the text as it is written, and each tool as it runs.

The editor is **you**, not a separate user: it is paired with the person
Donkey already knows on Telegram, Slack, Teams or another channel, so it
shares your memory and your conversation. What you said on your phone this
morning is there in the editor this afternoon.

```
Zed ──ACP (stdio)──► donkey acp ──HTTPS──► daemon gateway ──► your session
                                           /v1/acp/chat/completions
```

## Setting it up

1. **Reach the daemon's gateway.** On the daemon's machine the gateway is
   `http://127.0.0.1:8080`. From another machine, put a TLS reverse proxy in
   front of it and use its `https://` address (the gateway speaks plain HTTP;
   see [interfaces](interfaces.md)).
2. **Install the `donkey` binary on the editor's machine** (the nightly build
   or `nimble build`). `donkey acp` needs no configuration file.
3. **Tell the editor about it.** In Zed, add an agent server to
   `settings.json`:

   ```json
   {
     "agent_servers": {
       "Donkey": {
         "command": "donkey",
         "args": ["acp", "https://donkey.example.com"]
       }
     }
   }
   ```

   The URL can also come from `DONKEY_ACP_URL`; without either, `donkey acp`
   uses `http://127.0.0.1:8080`.

## Pairing

The first message from a new editor pairs it:

1. The editor's chat shows a code: *"mande `/editor K7QP2M` numa conversa com
   o Donkey onde ele já te conhece"*.
2. You send `/editor K7QP2M` to Donkey on Telegram (or any channel where it
   knows you). The code lives ten minutes.
3. The editor says it is connected and answers your message.

The editor keeps its credential in `~/.config/donkey/acp_credentials.json`
(0600), one per daemon URL. The daemon keeps only its hash.

To see or disconnect your editors, send `/editor` on any channel
(`/editor revogar <id>` disconnects one). The operator has `donkey ctl editor
list` and `donkey ctl editor revoke <id>`. A disconnected editor says so on
its next message, and pairs again.

## What the editor sees

- **Text** arrives in pieces, as the model writes it.
- **Tools** appear as they start (`bash`, `fs_read`, `web_search`…), with a
  kind for the editor's icon, and are marked done when the next text or tool
  arrives.
- **Files attached to the prompt** (the editor's `@file`) arrive in the turn
  as `<file uri="…">…</file>` blocks; a link without contents is named.
  Images and audio are not offered.
- **Approvals** for tools that need one (`bash`, `edit_file`…) appear in the
  editor as a permission prompt: allow once, allow always (where offered) or
  reject. Dismissing the prompt, or cancelling the turn, rejects.
- **Cancel** in the editor stops the turn; the daemon drops its late answer.

## Limits

- One prompt at a time per editor; a second while one runs is refused.
- Every editor session is your one Donkey conversation: opening two editor
  threads does not split it.
- The editor's own file reading and terminal (`fs/*`, `terminal/*`) are not
  used: Donkey's tools run on the daemon's side, in its sandbox.
