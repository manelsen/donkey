# Moltis API Migration Guide

This document provides a comprehensive index of all 49 crates in the Moltis workspace, their purpose, and main APIs.

## Architecture Overview

Moltis is a modular AI agent gateway organized around:

- **Core Services**: Agents, Config, Sessions, Channels, Providers
- **Gateway**: Central HTTP/WebSocket server (routes, auth, methods)
- **Channels**: 10+ message platforms (Telegram, Discord, Slack, etc.)
- **Tools**: Extensible tool system (shell, browser, web_fetch, etc.)
- **Memory**: Vector storage and retrieval
- **Apps**: Courier (APNS relay), iOS/macOS clients

---

## Crate Index

### Core Services

#### `moltis-agents`
**Purpose**: LLM agent runtime - model selection, prompt building, tool execution, streaming.

**Main APIs**:
- `ChatMessage`, `ContentPart`, `UserContent` - Message types
- `AgentRunError` - Error handling
- `AgentTool`, `ToolRegistry` - Tool system
- `run_agent_loop_streaming()` - Main execution loop
- `build_system_prompt_*()` - Prompt construction

**Key Modules**:
- `runner` - Agent execution
- `prompt` - System prompt building
- `tool_registry` - Tool management
- `multimodal` - Image/media handling

---

#### `moltis-auth`
**Purpose**: Authentication and credential management.

**Main APIs**:
- `CredentialStore` - SQLite-backed storage for passwords, passkeys, API keys, sessions
- `WebAuthnRegistry`, `WebAuthnState` - WebAuthn (passkey) challenges
- `has_proxy_headers()`, `is_local_connection()` - Connection locality detection
- `load_passkeys()` - Passkey loading

**Key Modules**:
- `credential_store` - Credential persistence
- `webauthn` - Passkey support
- `locality` - Network locality detection

---

#### `moltis-config`
**Purpose**: Configuration loading, validation, env substitution, legacy migration.

**Main APIs**:
- `MoltisConfig` - Root config type
- `load_config()`, `save_config()` - Config I/O
- `AgentIdentity`, `UserProfile` - Identity types
- `ToolMode`, `MessageQueueMode` - Execution modes
- `generic_provider_env()` - Provider env resolution

**Key Modules**:
- `loader` - Config file loading
- `schema` - Config type definitions
- `validate` - Validation logic
- `env_subst` - `${ENV_VAR}` substitution

**Config Files**: `moltis.toml`, `moltis.yaml`, or `moltis.json`

---

#### `moltis-sessions`
**Purpose**: Session storage and management.

**Main APIs**:
- `SessionKey` - Session identifier
- `PersistedMessage`, `MessageContent`, `ContentBlock` - Message types
- `SessionStore` - Session persistence
- `run_migrations()` - Database migrations
- `SearchResult` - Search results

**Key Modules**:
- `store` - Session persistence
- `compaction` - Session summarization
- `message` - Message types
- `metadata` - Session metadata

**Storage**: JSONL files at `<data_dir>/agents/<agentId>/sessions/<sessionKey>.jsonl`

---

#### `moltis-channels`
**Purpose**: Channel plugin system - defines traits for all message platforms.

**Main APIs**:
- `ChannelPlugin` - Main channel trait
- `ChannelConfig`, `ChannelAccountConfig` - Config types
- `ChannelEvent`, `ChannelEventSink` - Event system
- `ChannelOutbound`, `ChannelMessageKind` - Message sending
- `ChannelRegistry` - Plugin registry
- `ChannelDescriptor` - Channel metadata

**Key Modules**:
- `plugin` - Plugin trait definitions
- `registry` - Plugin management
- `message_log` - Message logging
- `otp` - OTP verification

---

#### `moltis-providers`
**Purpose**: LLM provider abstraction (OpenAI, Anthropic, Ollama, etc.).

**Main APIs**:
- `ProviderRegistry` - Provider management
- `ProviderError` - Error types
- `StreamEvent` - Streaming events
- `run_inference()` - Main inference endpoint
- `list_models()` - Model enumeration

**Key Modules**:
- `registry` - Provider registration
- `router` - Provider selection
- `anthropic`, `openai`, `ollama` - Provider implementations

---

#### `moltis-gateway`
**Purpose**: Central HTTP/WebSocket server, protocol dispatch, session/node registry.

**Main APIs**:
- `GatewayState` - Server state
- `Routes` - HTTP routes
- `WebSocket handlers` - Real-time communication
- `Auth middleware` - Authentication
- `Method handlers` - RPC endpoints

**Key Modules**:
- `chat` - Chat endpoints
- `auth_routes` - Authentication routes
- `channel` - Channel management
- `nodes` - Node registry
- `methods` - RPC method handlers

---

### Tools

#### `moltis-tools`
**Purpose**: Extensible tool system for agent actions.

**Main APIs**:
- `AgentTool` - Tool trait
- `ToolRegistry` - Tool registration
- `ToolPolicy` - Execution policies
- `ToolResult` - Tool output types

**Available Tools**:
- `shell` - Command execution
- `web_fetch` - HTTP requests
- `web_search` - Search providers
- `file_read`/`file_write`/`file_edit` - File operations
- `browser` - Browser automation
- `memory_store`/`memory_recall` - Memory operations
- `schedule` - Cron scheduling
- `screenshot` - Screenshots

---

### Memory

#### `moltis-memory`
**Purpose**: Memory management - markdown files → chunked → embedded → hybrid search in SQLite.

**Main APIs**:
- `MemoryStore` - Main storage interface
- `search()` - Vector + keyword search
- `write()` - Memory writing
- `run_migrations()` - Database setup

**Key Modules**:
- `store_sqlite` - SQLite persistence
- `chunker` - Text chunking
- `embeddings_openai`/`embeddings_local` - Embedding providers
- `search` - Hybrid search (BM25 + vector)

**Features**: Hybrid search (keyword + vector), SQLite with FTS5, multiple embedding backends

---

### Channels (Message Platforms)

#### `moltis-telegram`
**Purpose**: Telegram channel plugin.

**Main APIs**:
- `TelegramPlugin` - Plugin implementation
- `TelegramAccountConfig` - Config type
- `start_polling()` - Bot polling loop

**Features**: Bot API, inline messages, streaming updates, slash commands

---

#### `moltis-discord`
**Purpose**: Discord channel plugin.

**Main APIs**:
- `DiscordPlugin` - Plugin implementation
- `DiscordAccountConfig`, `ActivityType`, `OnlineStatus` - Config
- `gateway handler` - Discord Gateway events

**Features**: Gateway WebSocket, slash commands, rich embeds

---

#### `moltis-slack`
**Purpose**: Slack channel plugin.

**Main APIs**:
- `SlackPlugin` - Plugin implementation
- `SlackAccountConfig` - Config type
- WebSocket/Events API - Dual transport support

---

#### `moltis-whatsapp`
**Purpose**: WhatsApp channel plugin.

**Main APIs**:
- `WhatsappPlugin` - Plugin implementation
- `WhatsappAccountConfig` - Config type
- Business API - Cloud API support

---

#### `moltis-msteams`
**Purpose**: Microsoft Teams channel plugin.

**Main APIs**:
- `MsteamsPlugin` - Plugin implementation
- `MsteamsAccountConfig` - Config type
- Bot Framework - MS Bot Framework adapter

---

#### Other Channels
- `moltis-signal` - Signal messaging
- `moltis-matrix` - Matrix federation
- `moltis-line` - Line messaging
- `moltis-qq` - QQ (Tencent)
- `moltis-lark` - Lark (Feishu)
- `moltis-dingtalk` - DingTalk
- `moltis-email` - Email gateway
- `moltis-imessage` - iMessage (macOS)
- `moltis-mattermost` - Mattermost
- `moltis-teams` - Microsoft Teams

---

### Supporting Services

#### `moltis-auto-reply`
**Purpose**: Inbound message processing pipeline - glue between channels and agents.

**Main APIs**:
- `process_message()` - Main pipeline
- `normalize()` - Message normalization
- `chunk()` - Response chunking

**Flow**: Channel → Normalize → Route → Load Session → Media → Directives → Agent → Chunk → Deliver

---

#### `moltis-media`
**Purpose**: Media pipeline - download, store, MIME detect, image resize, audio transcription, serve.

**Main APIs**:
- `MediaStore` - Media storage
- `download()` - Media download
- `resize_image()` - Image operations
- `transcribe_audio()` - Audio-to-text

**Features**: Local storage, deduplication, TTL cleanup

---

#### `moltis-cron`
**Purpose**: Scheduled agent runs with cron expressions.

**Main APIs**:
- `CronStore` - Job persistence
- `schedule()` - Job scheduling
- `run_migrations()` - Database setup

**Storage**: JSONL at `<data_dir>/cron/jobs.json` or SQLite

**Features**: Isolated agent execution, optional channel delivery

---

#### `moltis-mcp`
**Purpose**: MCP (Model Context Protocol) client support.

**Main APIs**:
- `McpClient` - MCP client
- `McpManager` - Server lifecycle
- `McpRegistry` - Server registry
- `McpAgentTool` - Tool bridge

**Features**: JSON-RPC 2.0, stdio/HTTP transports, OAuth providers

---

#### `moltis-browser`
**Purpose**: Managed Chrome/Chromium with CDP for screenshots, snapshots, page interaction.

**Main APIs**:
- `BrowserManager` - Browser lifecycle
- `BrowserRequest`, `BrowserResponse` - Request/response types
- `BrowserAction` - Actions (navigate, screenshot, click, etc.)

**Actions**:
- `Navigate` - Navigate to URL
- `Screenshot` - Full page or viewport
- `Snapshot` - DOM with element refs
- `Click` - Click by element number
- `Type` - Input text
- `Scroll` - Scroll page/element
- `Evaluate` - Execute JavaScript
- `Wait` - Wait for elements

---

#### `moltis-canvas`
**Purpose**: Canvas/A2UI host - HTTP + WebSocket server for agent-controlled HTML UI.

**Main APIs**:
- `CanvasServer` - HTTP/WebSocket server
- `push()` - Push HTML to clients

**Flow**: Agent → canvas.push → Serve HTML → WebView → User → Event → Agent

---

#### `moltis-graphql`
**Purpose**: GraphQL API for Moltis - typed schema mirroring RPC interface.

**Main APIs**:
- `MoltisSchema` - GraphQL schema
- `build_schema()` - Schema builder
- Queries, mutations, subscriptions

**Endpoint**: `/graphql` (GraphiQL on GET, queries on POST, subscriptions via WebSocket)

---

#### `moltis-web`
**Purpose**: Web UI assets and server.

**Main APIs**:
- `WebServer` - Static asset server
- `GonData` - Server-injected data

**Assets**: JS, CSS, HTML in `crates/web/src/assets/`

**Features**: Dev mode (disk), release mode (embedded via `include_dir!`)

---

#### `moltis-cli`
**Purpose**: Command-line interface.

**Main APIs**:
- CLI commands: `moltis start`, `moltis auth`, `moltis sandbox`, etc.
- `Command` - Command trait

**Key Commands**:
- `start` - Start gateway
- `auth` - Auth management
- `sandbox` - Sandbox operations
- `agent` - Agent management
- `session` - Session operations

---

#### `moltis-voice`
**Purpose**: Voice features - STT/TTS providers.

**Main APIs**:
- `VoiceSttConfig`, `VoiceTtsConfig` - Config types
- `transcribe()` - Speech-to-text
- `synthesize()` - Text-to-speech

**Providers**:
- Whisper (OpenAI)
- ElevenLabs
- Local (whisper.cpp)

---

#### `moltis-skills`
**Purpose**: Skill system - discoverable skill packages.

**Main APIs**:
- `SkillDiscoverer` - Skill discovery
- `Skill` - Skill type
- `discover()` - Find skills

---

#### `moltis-plugins`
**Purpose**: Plugin hooks system.

**Main APIs**:
- `HookRegistry` - Hook management
- `Hook` - Hook trait
- `register()` - Register hooks

**Hook Types**:
- `ShellHook` - Shell command hooks
- `BootMdHook` - Markdown boot hooks

---

#### `moltis-tls`
**Purpose**: TLS certificate management.

**Main APIs**:
- `CertManager` - Certificate lifecycle
- `generate()` - Generate certificates

---

#### `moltis-network-filter`
**Purpose**: SSRF protection, IP filtering.

**Main APIs**:
- `is_allowed()` - IP validation
- `filter()` - Request filtering

**Protection**: Blocks loopback, private IPs, link-local, CGNAT

---

#### `moltis-service-traits`
**Purpose**: Service trait definitions for RPC/GraphQL.

**Main APIs**:
- `Services` - Service bundle
- Individual service traits

---

#### `moltis-schema-export`
**Purpose**: Schema export utilities.

---

#### `moltis-swift-bridge`
**Purpose**: Swift interop for iOS/macOS apps.

---

#### `moltis-vault`
**Purpose**: Secret vault integration.

---

#### `moltis-common`
**Purpose**: Shared types, error definitions, utilities.

**Main APIs**:
- `Error`, `Result` - Common error types
- `MoltisError` - Error trait
- `FromMessage` - Message conversion

---

#### `moltis-node-host`
**Purpose**: Node host management.

---

#### `moltis-qmd`
**Purpose**: QMD (Query Modulation and Distribution) - retrieval strategies.

---

#### `moltis-routing`
**Purpose**: Message routing logic.

---

#### `moltis-protocol`
**Purpose**: Protocol definitions.

---

#### `moltis-provider-setup`
**Purpose**: Provider setup wizards.

---

#### `moltis-onboarding`
**Purpose**: User onboarding flow.

---

#### `moltis-openclaw-import`
**Purpose**: Import from OpenClaw.

---

#### `moltis-projects`
**Purpose**: Project management.

---

#### `moltis-wasm-precompile`
**Purpose**: WASM precompilation.

---

#### `moltis-wasm-tools`
**Purpose**: WASM tooling.

---

### Apps

#### `courier`
**Purpose**: Privacy-preserving APNS push relay for Moltis gateways.

**Main APIs**:
- `main()` - Server entrypoint
- `handle_push()` - Push endpoint
- `handle_health()` - Health check

**Features**: Holds single .p8 key, forwards silent pushes, no message visibility

**Endpoint**: `/push` (POST), `/health` (GET)

---

#### `ios`
**Purpose**: iOS client application.

---

#### `macos`
**Purpose**: macOS client application.

---

### Utilities

#### `moltis-benchmarks`
**Purpose**: Benchmark suite.

---

#### `moltis-caldav`
**Purpose**: CalDAV integration for calendar operations.

**Main APIs**:
- `CalDavClient` - CalDAV client
- `CalDavTool` - Agent tool
- `discovery()` - Server discovery

**Features**: Fastmail, iCloud, generic CalDAV support

---

#### `moltis-tailscale`
**Purpose**: Tailscale integration.

---

## File Location

**Skeletons**: `/home/micelio/git/donkey/docs/blueprint/moltis/`
**Source**: `/home/micelio/git/donkey/inspiration/moltis/`

## Statistics

- **Total Crates**: 49
- **Total Rust Files**: 480
- **Apps**: 3 (courier, ios, macos)
- **Channels**: 10+ platforms

## Migration Notes

### Dependencies

Most crates depend on:
- `moltis-common` - Shared types
- `moltis-config` - Configuration
- `moltis-auth` - Authentication
- `moltis-sessions` - Session storage
- `moltis-channels` - Channel traits
- `moltis-providers` - LLM providers

### Key Patterns

1. **Traits over impls**: Most functionality exposed via traits (`ChannelPlugin`, `AgentTool`, etc.)
2. **Async everywhere**: All I/O is async (`tokio`)
3. **Error handling**: `anyhow::Result` for apps, `thiserror` for libraries
4. **Streaming**: Use streaming APIs (`StreamEvent`, `StreamReceiver`)
5. **Secrets**: Use `secrecy::Secret<String>` for sensitive data

### Database Migrations

Crates with SQLite databases have `run_migrations()`:
- `moltis-sessions` - `sessions`, `channel_sessions` tables
- `moltis-cron` - `cron_jobs`, `cron_runs` tables
- `moltis-memory` - `files`, `chunks`, `embedding_cache` tables
- `moltis-projects` - `projects` table
- `moltis-gateway` - `auth_*`, `passkeys`, `api_keys`, `env_variables`, `message_log`, `channels` tables

### Config

All config in `moltis.toml` (or YAML/JSON):
- Profiles per agent
- Provider API keys
- Channel accounts
- Voice/media settings
- Memory scope
- Tool policies
