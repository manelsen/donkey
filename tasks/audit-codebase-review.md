# Code Audit: Idioms, Duplication and SRP

Date: 2026-11-20. Base: `feat/command-dispatch-app` (68cf85ad).
Method: automated scans of the whole tree (imports, exceptions, I/O, env reads, dependency graph from `src/donkey.nim`, duplicated 8-line windows), followed by reading the modules the scans flagged. Counts are reproducible with the commands in the appendix.

Size: 313 modules and 76k lines in `src/`. `CLAUDE.md` still says 30k lines and 149 files.

## P1: correctness and security

### 1. The production provider bypasses `HttpPort` and has no timeout
`buildGlobalProviderBundle` (`src/donkey.nim:437`) builds the global `completeFn`/`streamFn` from `OpenRouterAdapter`. That adapter uses `withHttpClient` (`adapters/http/helpers.nim:6`), which calls `newHttpClient()` with no timeout. It also skips the allowlist, the egress proxy and the circuit breaker of `StdHttpAdapter`. A stalled provider blocks the turn indefinitely.
The same template is used by `openai`, `anthropic`, `ollama`, `zhipu`, `gemini`, `deepseek` and `minimax`. `compat_adapter` streaming uses `newHttpClient` with a timeout but also outside the port.
This contradicts `CLAUDE.md`: "Todos os adapters usam `HttpPort` para I/O HTTP, nunca `std/httpclient` diretamente."
**Fix:** give `HttpPort` a streaming operation, or at least route every provider through `withHttpClientTimeout` with the egress settings. Then remove `withHttpClient`.

**Status:** done in `fix/provider-http-port` (#77). Every provider posts through `HttpRuntimePort` with a 120 s timeout, no redirects and no repeated POST; a final 5xx keeps the provider name and body.

**Remaining gap (found in the #77 review):** the `std/httpclient` timeout is per read, not per request. In Nim 2.2.8 it covers neither `net.dial` (`httpclient.nim:1057`) nor the chunk-size line (`httpclient.nim:793`), and a server that sends a byte now and then never trips it. This holds for every `StdHttpAdapter` user (providers, channels) and for `clawhub_registry`. A wall-clock deadline for the whole request needs a different transport in which every blocking step (connect, header and chunk-size reads, body reads) is bounded by the time left or can be cancelled when the deadline passes, for example Chronos `HttpSessionRef` with a request deadline. Checking the deadline only between reads is not enough: a read that blocks forever never reaches the next check.

### 2. `except Exception` in 96 places
`except Exception` also catches `Defect` (index errors, nil access, assertion failures), so programming errors turn into "unavailable" results instead of crashing loudly. The worst files are `md_file.nim` (16), `session_bootstrap.nim` (11), `subagent_runtime.nim` (9), `fs_tools.nim` (7) and `onboarding_runtime.nim` (6). There are also 9 bare `except:` (for example in `core/commands/command_routing.nim:327,334`, `config/loader.nim:305` and `app/doctor.nim:39`).
**Fix:** use `except CatchableError` everywhere except where a `{.raises: [].}` boundary really needs `Exception`, and comment those.

### 3. Send failures dropped silently
There are 84 `isOkOr:` handlers in total, and 17 end in a bare `discard`. Most are user replies in channel runtimes: `qq_runtime` (keyboards and confirmations), `telegram_runtime` (ping, status and the legacy UI) and `src/donkey.nim`. A failed reply leaves no trace in the logs.
**Fix:** log at least at `warn` level, or return `Result` to the caller.

## P2: SRP and layering

### 4. `src/donkey.nim` is more than a composition root
It has 2381 lines and 91 procs. Besides wiring, it holds:
- route-health persistence and metrics: `saveRecentRouteSamples`, `pruneProviderCooldowns`, `topRouteMetrics` and related procs (lines 604–910);
- the IPC server (`setupIpcServer`, about 176 lines);
- filesystem operations for subagent paddocks;
- the inbound-reaction status policy;
- CLI help;
- 87 `getEnv` calls.

**Fix:** move route health into `app/route_health.nim`, IPC into `app/ipc_server.nim` (which already exists), and the paddock operations into an adapter behind `SubagentWorkspacePort`. Read the environment once into the configuration.

### 5. `MdFileAdapter` and `MemoryRuntimePort` mix five responsibilities
They cover memory/profile, the DM allowlist (`isDmAllowed`/`addDmAllowed`), reminders (`scheduleReminder`/`loadDueReminders`), identity (`saveIdentity`), transcript search and user revocation. The port inherits the mix, so every memory backend has to implement reminders and the allowlist.
**Fix:** split into `ReminderPort`, `AllowlistPort` and `IdentityPort`. The MdFile store can keep implementing all of them, but each should sit behind its own port.

### 6. `app/http_gateway.nim` is a 1394-line monolith

**Progress:** the gateway now runs on the Chronos loop (no worker threads, no global callbacks, no locks; the agent turn and its stream are `async`). The split into pure modules is still open.

**Follow-up from the move:** the gateway shares the main loop with the channel adapters, whose HTTP calls are synchronous. A stalled channel API now delays the gateway too, as it already delayed the session actors. The fix for all of them is the async `HttpPort` (`ChronosHttpAdapter`).
It contains bearer auth, routing, the dashboard HTML, SSE, connection admission and limits, request parsing and the thread pool.
**Fix:** move auth and routing into pure modules (some already exist in `domain/gateway/`), keep socket I/O in an adapter, and keep use-case orchestration in `app`.

### 7. `app/native_tools.nim` calls itself a "thin dispatch layer" but is not
It holds about 25 `parse*Context` functions (argument parsing and validation) and the `execute*NativeTool` procs.
**Fix:** move the parsers to `domain/tools/` as `func`s, and keep only dispatch in `app`.

### 8. Raw I/O in `app`
`app/tools/*` (`fs_tools` 14, `search_tools` 4 and others), `sandbox`, `heartbeat`, `service_handler` and `setup_wizard` call `readFile`, `writeFile`, `execProcess` and `walkDir` directly, even though `ports/fs.nim` exists. This makes it impossible to test with fakes and inconsistent with providers and channels.

### 9. Scattered configuration
There are 127 `getEnv` calls outside `config/` (59 in `app/`, 62 in `adapters/`, plus 87 in `src/donkey.nim`). `adapters/channel/command_services.nim` alone has 25 (`/about` and `/doctor` read the environment to list channels and keys).
**Fix:** read the environment once into `DonkeyConfig` and inject it.

### 10. Pending items from PR #75
- ~~The `/models`, `/think` and `/budget` policy is still in `command_services` (an adapter).~~ Done in 0.3.0 (see the checklist below).
- ~~`command_text.nim` mixes texts, argument parsing and availability, so `ports/channel_capability` imports a text module.~~ Done: availability is `core/commands/command_surface`, arguments `core/commands/command_args`, texts stay in `command_text`; ports import only the surface (checked by `check_boundaries.sh`).
- ~~`channel_prefs_store` produces presentation text (`buildConfigText`).~~ Done: the store only reads and writes; the /config view is `configViewText` in the channel layer (`common_runtime`), and the memory store may not import command texts (checked).
- ~~`model_catalog_ui` reads preferences from storage.~~ Done in 0.3.0: the buttons take the current selection as data.
- ~~`CommandServicesPort` carries counters.~~ Done: the tool counts are a query (`toolCounts`), so the port holds operations only.

**Reminder (owner asked to be reminded; from the #79 review of the #75 code):**
- [x] Move the `/models`, `/think` and `/budget` policy out of `adapters/channel/command_services.nim` (0.3.0). `core/commands/preference_commands` holds what an argument means, the selection check against catalog and menu, the answers and the catalog presentation (pure, with the menu, the catalog and the time passed in). `app/preference_commands` runs it over a read and a save proc (tested with an in-memory store). The adapter only builds those procs from the Markdown/MAGMA store and the catalog loader.
- [x] Make preference reads return `Result` (0.3.0). `readPreferences` reads what the store holds (graph, file, or an error when the graph is unavailable or the file unreadable), and `loadChannelPrefs`, `loadChannelPreference`, `getCurrentProviderModel`, `getCurrentThinkLevel`, `getCurrentBudgetPolicy` and `buildConfigText` return `Result`; a malformed PREFERENCES.md is an error too (`tryParseChannelPrefs`). Each caller decides: commands and pickers tell the user the preferences cannot be read; /status, /about and ping fail with that message; /doctor reports it and goes on; the Discord reasoning toggle refuses instead of flipping the default; the Discord offline cursor skips the user for that round instead of reading "no cursor" (which marks the history as seen).

## P3: duplication and dead code

### 11. 39 modules (about 8.4k lines, 11% of the code) outside the binary — DONE

Resolved in `chore/remove-dead-modules`: all 39 modules and the 38 tests that covered only them were deleted ("a melhor refatoração é apagar o que é inútil"). What is needed again will be rebuilt.

None of these is reachable from `src/donkey.nim`. They are kept alive only by tests.

| Family | Modules | Note |
|---|---|---|
| Tool adapters replaced by `app/tools/` | `adapters/tools/{fs,shell,git,web_fetch,mcp_client}` | The production MCP client is `adapters/tool/mcp_client.nim` (singular directory). |
| Previous Markdown memory | `adapters/memory/markdown.nim` | Shares windows with `md_file.nim`. |
| Previous routing and failover | `domain/routing/{smart_route,failover}`, `core/providers/provider_failover` | Duplicates `core/providers/smart_routing`. |
| Turn journal | `adapters/state/turn_journal_store` (996), `domain/session/turn_journal_pure` (496) | About 1.5k lines with tests that are never wired. |
| Sandbox | `infra/sandbox/{docker,wasm,limits,paddock}` | About 1.35k lines, not wired. |
| Hooks | `ports/hook`, `core/hooks/*`, `adapters/hooks/*` | The whole hooks feature is not wired. |
| Others | `core/actor`, `adapters/provider/zen`, `app/agent_runner`, `adapters/memory/{age_store,postgres_memory,sqlite_store}`, `qq_webhook`, `line_{admission,outbox}`, `domain/{compaction_pure,identity,usage_tracking,model_limits}` | Some may be planned F2+ features; mark them as such or remove them. |

**Decision needed:** for each family, wire it, mark it as F2+ (and exclude it from the "simple first" count), or delete it.

### 12. Patterns copied with variations
- **Access-token cache:** four implementations (`wecom`, `qq_official`, `dingtalk`, `qq_webhook`).
- **Event queue:** 12 global `Channel[...]` per adapter, each with its own `pushEvent`/`tryRecvEvent`/`openQueue`.
- **Message splitting:** `core/pipeops.splitChunks`, `domain/channels/telegram_split.splitForTelegram`, `adapters/channel/line.splitForLine` and 8 variants in `domain/memory/chunking`.
- **LLM reranking:** `minimax_rerank` and `zai_rerank` are near copies (4 shared windows), as is part of `openrouter_rerank`.
- **SQLite stores:** `schedule_store`, `turn_journal_store` and `runtime_store` repeat open, migrate and transaction boilerplate.
- **Graph store:** `magma_graph` and `sqlite_magma_store` share query blocks.
- **Help:** `qqHelpText` and `buildWeComHelpMd` rebuild the help text by hand.
- **Session tasks:** Discord buttons, Telegram callbacks and Slack onboarding enqueue tasks without `enqueueSessionTask`.

### 13. `CLAUDE.md` conventions not followed
- 19 modules in `domain/` return `Result`, and there are 43 `proc`s in `domain/` (the rule is pure `func`). This needs the ADR already listed as an open question in the command-dispatch PRD.
- 29 modules import `results` directly instead of `pipeops`.
- **ORC or YRC: decided, ORC.** A lock protects the data, not the reference count of a `ref` shared between threads, which ORC does not update atomically. YRC would make every count atomic (about 2x the cost) to cover sharing the code no longer does. Instead, nothing GC-counted crosses a thread, and the compiler checks it: `spawnThread` refuses an argument holding a ref or a closure (`sharesNothing`, `infra/thread_handle`), and `tests/architecture/t_thread_spawning.nim` allows a direct `createThread` only in the three listed places. Threads that need a closure build it themselves from plain data or a `nimcall` factory. What the audit found, and how each ended:
  - `core/identity/link_codes.nim`: the `LinkCodeService` ref is shared by the resolvers, which all live on the daemon loop; `ThreadOwner` reports any other thread. Stays.
  - `adapters/channel/slack_socket.nim`: the reader thread got a copy of the daemon's `HttpRuntimePort` closures. Fixed: it receives a `nimcall` `SlackHttpFactory` and builds its port.
  - `app/tool_loop_runtime.nim` (`streamToOutbox`): every streaming turn ran the one global `StreamFn` on its own thread. Fixed in #92 (`StreamFactory`, stream cap, background reaping).
  - Email and Signal polling (found by the new check's sweep): the poll threads got a pointer to the loop's adapter and ran its `IdentityResolver` (which may write the identity file) concurrently with the loop. A data race, not only a counting one. Fixed: the threads get plain data (`EmailInbox`, the socket path) and return unresolved senders; identities are resolved on the loop.
  - `Logger` (found by the check): its `sink` is a closure, so eight thread arguments carried one. Production sinks have no environment, but nothing guaranteed it. Fixed: thread arguments carry a `LogSpec` (subsystem and level) and the thread rebuilds its logger.
- **Diet done: zero casts.** No `{.cast(gcsafe).}` and no `{.gcsafe.}:` block remain; the ratchet allows none, explained or not. Cross-thread state lives in `infra/` (event queues, thread handles, fixed-capacity text and tables under a lock); single-thread state is a threadvar checked by `infra/thread_owner`; TOML is parsed by `config/toml` (parsetoml dropped). History: `tests/architecture/t_gcsafe_casts.nim` caps the unexplained casts (130 when it started) and the budget only goes down. Families, in the planned order: global callbacks (closures shared across threads, the class that crashed the provider executor under Nim 2.4), per-adapter event queues (with item 12), logging, thread handles and flags, locked global state, the rest. The ORC vs YRC choice (ORC, below) and the move to Nim 2.4.2 followed: on 2.4.2 the provider executor still crashed, because closures built on the loop and moved to a worker stay in the loop thread's ORC cycle roots; the workers now build their own bundles.
- There are 134 `{.cast(gcsafe).}`, concentrated in `session_manager` (10), `metrics` (9) and `http_gateway` (7). Each one is an unchecked promise. Prefer locks with `{.gcsafe.}` on the procs, or move the state out of globals.
- About 60 `except Exception` remain, each marked `## effect boundary`. The cause is a callee without `raises`: port closures (`MemoryRuntimePort.loadContext`, `CompleteFn`, `SearchFn` users) and forward declarations without `raises`, which Nim treats as raising `Exception` (found in `md_file.nim`). `scheduleReminder` was annotated in #78 as the pattern: port field, forward declaration and closure get `raises: [CatchableError]`, and the handler narrows. `loadContext` needs the MAGMA graph closures annotated first.
- The documentation says ports are `concept`s, but most of them (`MemoryRuntimePort`, `LinkCodePort`, `CommandServicesPort`) are objects of closures. The text should describe both styles.

## Suggested order

1. P1 items 1–3: small, independent changes with high risk if left as they are.
2. Item 11: decide what is dead before refactoring it (it reduces the scope of the rest).
3. Items 4 and 9 (composition root and configuration), which simplify 5–8.
4. Items 5–8 and 12, one PR per family.
5. Items 10 and 13, together with the domain/`Result` ADR.

## Appendix: commands

```
rg -n 'except Exception' src | wc -l
rg -n '^\s*except:\s*$' src
rg -n -A1 'isOkOr:\s*$' src | grep -c -- '-\s*discard$'
rg -c 'getEnv\(' src/donkey/app src/donkey/adapters src/donkey.nim
rg -ln 'withHttpClient\b' src
python3 scripts/audit/deadmods.py   # reachability from src/donkey.nim
python3 scripts/audit/dups.py       # duplicated 8-line windows (normalized)
```
