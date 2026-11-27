# MCP servers
Connecting Model Context Protocol servers to Donkey.

MCP servers run directly on the host and inherit the daemon environment, which
may contain credentials: install only trusted servers, or isolate them
externally.

## A server over stdio

```bash
# Positional arguments only via CLI
./donkey ctl tool install <mcp-server-command> [positional-args...]
```

> [!TIP]
> Server flags like `--port=8000` are filtered out by the CLI option parser; configure MCP servers requiring flags directly in `tools.toml` under your configured home directory (`cfg.home/tools.toml`, which defaults to `~/.donkey/tools.toml`).

## A server over Streamable HTTP

A remote server over Streamable HTTP (MCP 2025-06-18) is registered by URL. `https` is required off this machine; a bearer, when the server needs one, is read from the environment variable you name, and only that name is written to `tools.toml`:
```bash
./donkey ctl tool add-http https://mcp.example.com/mcp --token-env EXAMPLE_MCP_TOKEN
```

A server that uses OAuth (MCP authorization, 2025-06-18) is registered with `--oauth`, which logs in right away; `ctl mcp login <url>` logs in again later. Donkey runs without a browser, so the CLI prints the authorization URL, you authorize in your own browser, and the browser is sent to `http://127.0.0.1:8976/callback`, which does not load (nothing listens there): copy the URL from the address bar and paste it into the CLI. The tokens are stored readable only by the daemon's user (`{home}/state/mcp_oauth/`) and refreshed automatically.
```bash
./donkey ctl tool add-http https://mcp.example.com/mcp --oauth
./donkey ctl mcp login https://mcp.example.com/mcp
```

When the authorization server has no dynamic registration, register a client with it yourself and log in with its id. A client with a secret keeps the secret in a variable (the vault or `donkey.env`); only the variable's name is stored with the tokens, and the secret is read again for each refresh.
```bash
./donkey ctl mcp login https://mcp.example.com/mcp --client-id my-app
./donkey ctl secret set MCP_EXAMPLE_SECRET
./donkey ctl mcp login https://mcp.example.com/mcp --client-id my-app --client-secret-env MCP_EXAMPLE_SECRET
```

## Sampling

A server over stdio may ask to run your model during a tool call (MCP sampling). Every request is shown to the person whose call it is, who approves it this time, always for that server (the approval follows the server's command and arguments, not its name), or denies it. Approved, it runs through that person's model route without tools, at most `DONKEY_MCP_SAMPLING_MAX_TOKENS` tokens per request (4096) and `DONKEY_MCP_SAMPLING_DAILY_TOKENS` per server per day (50000); past the daily cap it is refused without asking. Approvals that stand are listed and revoked with:

```bash
./donkey ctl approval standing list <user-id>
./donkey ctl approval standing revoke <user-id> <key>
```
