import json

tasks = []
task_id = 1

def add_task(title, desc, criteria, deps):
    global task_id
    id_str = f"US-{task_id:03d}"
    
    # Injecting the pipeops architectural constraint into every task
    architectural_constraint = "Code MUST use `pipeops.nim` (`|>` for pure, `|>->` for last-arg, `>>=` for Result binding) instead of imperative variable assignments where applicable."
    
    tasks.append({
        "id": id_str,
        "title": title,
        "description": desc,
        "acceptanceCriteria": criteria + [
            architectural_constraint,
            "nim build src --mm:orc --styleCheck:error --warnings:error passes",
            "testament pattern 'tests/**/*.nim' passes"
        ],
        "priority": task_id,
        "passes": False,
        "notes": "ARCHITECTURAL RULE: Follow the OCaml-style pipeline topology defined in src/donkey/core/pipeops.nim. Functions should be designed as unary or with the piped target as the last argument to facilitate `|>` and `|>->`.",
        "dependsOn": deps
    })
    task_id += 1
    return id_str

# ==========================================
# EPIC 1: Sovereign Foundation
# ==========================================
us_comp = add_task("Strict Compilation & Panics", "Enforce Nim compiler strictness for zero-ambiguity.", ["Add --styleCheck:error, --warnings:error, --panics:on"], [])
us_res = add_task("Result[T, E] & Pipeops Pervasiveness", "Eradicate try/except from business logic and enforce pipeops topology.", ["Ensure core/pipeops.nim is exported and used", "Refactor core to never raise, using `>>=` for chaining"], [us_comp])
us_actor = add_task("Actor Model Mailbox", "Resilient async message passing (inspired by BEAM/Pincer).", ["Implement lock-free or channel-based inbox/outbox in core/actor.nim"], [us_res])
us_diag = add_task("System Diagnostics (Doctor)", "CLI tool to verify external dependencies (DBs, binaries).", ["Implement `donkey doctor` checking for pgvector, docker, API keys"], [us_res])

# ==========================================
# EPIC 2: Security & Shield (Do this early so tools use it)
# ==========================================
us_sec_ssrf_pure = add_task("SSRF IP Validator (Pure)", "Detect local/private/bogon IPs to prevent internal network scanning.", ["Implement network.nim with isPrivateIp() parsing logic"], [us_res])
us_sec_ssrf_dns = add_task("SSRF DNS Resolver", "Resolve domains and block if they map to private IPs (nanobot style).", ["Implement safeResolve() adapter returning Result"], [us_sec_ssrf_pure])
us_sec_scan_pure = add_task("Secret Scanner & Entropy", "Detect API keys via Regex and Shannon Entropy (ironclaw style).", ["Implement secrets.nim with calculateEntropy() and regex masks"], [us_res])
us_sec_sanitize = add_task("Output Sanitizer", "Strip internal thought tags and mask secrets before user delivery.", ["Implement clean_response() via `|>` chaining"], [us_sec_scan_pure])

# ==========================================
# EPIC 3: Ingress, Identity & Channels
# ==========================================
us_ident = add_task("Cross-Channel Identity Map", "Map unique users across different platforms (Donkey F1).", ["Implement domain/identity.nim mapping platform IDs to internal UUIDs"], [us_res])
us_debounce = add_task("Adaptive Debounce", "Handle split messages based on timing/length (nullclaw style).", ["Implement pure message debounce/merge logic (1.2s to 8s window)"], [us_res])
us_ch_port = add_task("Hexagonal Channel Port", "Define the abstract interface for all incoming/outgoing messages.", ["Create ports/channel.nim with send(), receive() Result signatures"], [us_actor])

# Channels (Pure + Adapter pairs)
us_tg_pure = add_task("Telegram Parser (Pure)", "Parse TG updates into internal domain objects.", ["Implement domain/channels/telegram_pure.nim"], [us_ch_port])
us_tg_adap = add_task("Telegram IO Adapter", "HTTP long-polling or webhook adapter for TG.", ["Implement adapters/channels/telegram.nim using `>>=` for HTTP flows"], [us_tg_pure])

us_dc_pure = add_task("Discord Parser (Pure)", "Parse Discord gateway/webhook events.", ["Implement domain/channels/discord_pure.nim"], [us_ch_port])
us_dc_adap = add_task("Discord IO Adapter", "WebSocket or REST adapter for Discord.", ["Implement adapters/channels/discord.nim"], [us_dc_pure])

us_slk_pure = add_task("Slack Parser (Pure)", "Parse Slack Events API payload.", ["Implement domain/channels/slack_pure.nim"], [us_ch_port])
us_slk_adap = add_task("Slack Socket/Webhook Adapter", "Socket Mode and Webhook support.", ["Implement adapters/channels/slack.nim"], [us_slk_pure])

us_wa_pure = add_task("WhatsApp Parser (Pure)", "Parse WA Cloud API payloads.", ["Implement domain/channels/whatsapp_pure.nim"], [us_ch_port])
us_wa_adap = add_task("WhatsApp Webhook Adapter", "HTTP handler for WA.", ["Implement adapters/channels/whatsapp.nim"], [us_wa_pure])

us_sig_adap = add_task("Signal CLI DBus Adapter", "Communicate with signal-cli daemon via IPC/DBus.", ["Implement adapters/channels/signal.nim"], [us_ch_port])

# Chinese Ecosystem
us_wechat_pure = add_task("WeChat/WeCom Parser", "Handle WeChat XML/JSON quirks.", ["Implement domain/channels/wechat_pure.nim"], [us_ch_port])
us_wechat_adap = add_task("WeChat Webhook Adapter", "HTTP handler for WeChat.", ["Implement adapters/channels/wechat.nim"], [us_wechat_pure])

us_feishu_pure = add_task("Feishu/Lark Parser", "Handle Feishu event structures.", ["Implement domain/channels/feishu_pure.nim"], [us_ch_port])
us_feishu_adap = add_task("Feishu Webhook Adapter", "HTTP handler for Feishu.", ["Implement adapters/channels/feishu.nim"], [us_feishu_pure])

us_qq_pure = add_task("QQ Parser", "Handle QQ official bot events.", ["Implement domain/channels/qq_pure.nim"], [us_ch_port])
us_qq_adap = add_task("QQ Webhook Adapter", "HTTP handler for QQ.", ["Implement adapters/channels/qq.nim"], [us_qq_pure])

us_ding_pure = add_task("DingTalk Parser", "Handle DingTalk payloads.", ["Implement domain/channels/dingtalk_pure.nim"], [us_ch_port])
us_ding_adap = add_task("DingTalk Webhook Adapter", "HTTP handler for DingTalk.", ["Implement adapters/channels/dingtalk.nim"], [us_ding_pure])

# Others
us_matrix_adap = add_task("Matrix Synapse Adapter", "Client-server API for Matrix.", ["Implement adapters/channels/matrix.nim"], [us_ch_port])
us_email_adap = add_task("Email IMAP/SMTP Adapter", "Polling IMAP for inbox, SMTP for outbox.", ["Implement adapters/channels/email.nim"], [us_ch_port])
us_cli_repl = add_task("CLI REPL Interactive", "Local terminal loop with history.", ["Implement adapters/channels/cli_repl.nim chaining via `>>=`"], [us_ch_port])
us_web_sse = add_task("Web UI SSE Gateway", "Real-time log and agent event streaming (Donkey F1).", ["Extend http_gateway.nim for bidirectional SSE"], [us_ch_port])

# ==========================================
# EPIC 4: Providers, Routing & Resilience
# ==========================================
us_prov_port = add_task("Hexagonal Provider Port", "Define abstract LLM interface with streaming.", ["Create ports/provider.nim"], [us_res])
us_quirks = add_task("Provider Quirks Normalizer", "Normalize message blocks across Anthropic/OAI/Gemini.", ["Implement domain/providers/quirks.nim (pure)"], [us_res])

us_oai_pure = add_task("OpenAI Protocol (Pure)", "Format requests/responses for OpenAI/OpenRouter.", ["Implement domain/providers/openai_pure.nim"], [us_quirks])
us_oai_adap = add_task("OpenAI IO Adapter", "HTTP client for OAI API.", ["Implement adapters/providers/openai.nim"], [us_oai_pure, us_prov_port])

us_ant_pure = add_task("Anthropic Protocol (Pure)", "Format XML/JSON for Claude APIs.", ["Implement domain/providers/anthropic_pure.nim"], [us_quirks])
us_ant_adap = add_task("Anthropic IO Adapter", "HTTP client for Anthropic.", ["Implement adapters/providers/anthropic.nim"], [us_ant_pure, us_prov_port])

us_gem_pure = add_task("Gemini Protocol (Pure)", "Format requests for Google Gemini.", ["Implement domain/providers/gemini_pure.nim"], [us_quirks])
us_gem_adap = add_task("Gemini IO Adapter", "HTTP client for Gemini.", ["Implement adapters/providers/gemini.nim"], [us_gem_pure, us_prov_port])

us_ollama_pure = add_task("Ollama Protocol (Pure)", "Format requests for local GGUF models.", ["Implement domain/providers/ollama_pure.nim"], [us_quirks])
us_ollama_adap = add_task("Ollama IO Adapter", "HTTP client for Ollama.", ["Implement adapters/providers/ollama.nim"], [us_ollama_pure, us_prov_port])

us_deepseek_adap = add_task("DeepSeek Adapter", "OpenAI-compatible wrapper with DeepSeek specific reasoning extraction.", ["Implement adapters/providers/deepseek.nim"], [us_oai_pure])
us_zhipu_adap = add_task("Zhipu/GLM Adapter", "Adapter for Z.AI models.", ["Implement adapters/providers/zhipu.nim"], [us_oai_pure])

us_router_pure = add_task("Smart Routing Classifier", "Pure logic to pick provider based on task cost/complexity.", ["Implement domain/routing/smart_route.nim"], [us_res])
us_retry_pure = add_task("Failover State Machine", "Pure logic to handle API timeouts and fallback chains.", ["Implement domain/routing/failover.nim"], [us_res])

# ==========================================
# EPIC 5: Memory & Cognition (The Archive)
# ==========================================
us_mem_md = add_task("Markdown Memory FS Sync", "Sync MEMORY.md and USER.md to context (openclaw style).", ["Implement adapters/memory/markdown.nim using `>>=` for safe IO"], [us_res])
us_mem_sqlite = add_task("SQLite Fast Cache", "Store raw session logs locally for fast reboot.", ["Implement adapters/memory/sqlite_store.nim"], [us_res])

us_mem_chunk = add_task("Text Chunking & Hashing", "Pure logic to split text with overlap and SHA256 (openclaw style).", ["Implement domain/memory/chunking.nim using `|>` chaining"], [us_res])
us_mem_embed = add_task("Embedding Pipeline", "Coordinate chunking with Provider Port to get vectors.", ["Implement core/memory/embedder.nim via `>>=` chaining"], [us_mem_chunk, us_prov_port])

us_pg_adap = add_task("pgvector Adapter", "PostgreSQL schema and IO for vectors.", ["Implement adapters/memory/pgvector_store.nim returning Result"], [us_res])
us_rrf_pure = add_task("Reciprocal Rank Fusion", "Pure math to merge BM25 and Cosine Similarity scores (nullclaw style).", ["Implement domain/memory/rrf.nim"], [us_res])
us_temporal = add_task("Temporal Decay Penalty", "Pure logic to decay memory relevance over time.", ["Implement domain/memory/decay.nim"], [us_res])

us_graph_pure = add_task("Triple Extraction Logic", "Pure logic to parse Subject-Predicate-Object from text.", ["Implement domain/memory/graph_pure.nim"], [us_res])
us_graph_age = add_task("Apache AGE Adapter", "Execute Cypher queries against PostgreSQL (Pincer style).", ["Implement adapters/memory/age_store.nim"], [us_graph_pure])
us_silent_turn = add_task("Silent Memory Turn", "Background orchestrator loop to extract memories without user prompt (moltis).", ["Implement core/memory/silent_turn.nim"], [us_graph_age, us_pg_adap])
us_blackboard = add_task("Blackboard Scratchpad", "Short-term planning memory injected into context (Supernova style).", ["Implement core/memory/blackboard.nim"], [us_res])

# ==========================================
# EPIC 6: Tools & Sovereign Action
# ==========================================
us_tool_port = add_task("Native Tool Port", "Abstract interface for tool execution.", ["Create ports/tool.nim"], [us_res])

us_fs_path = add_task("Path Security Sandbox", "Pure function to block `../` and restrict to workspace.", ["Implement domain/tools/path_guard.nim"], [us_res])
us_fs_tools = add_task("File System Tools", "Native read_file, write_file, list_dir.", ["Implement adapters/tools/fs.nim chained with `>>=`"], [us_fs_path, us_tool_port])
us_git_tools = add_task("Git Introspection Tools", "Native git status, log, diff.", ["Implement adapters/tools/git.nim"], [us_tool_port])

us_shell_ast = add_task("Safe Shell AST", "Pure parser to detect/block shell operators (Pincer/Supernova style).", ["Implement domain/tools/shell_ast.nim blocking `;|&<>`"], [us_res])
us_shell_adap = add_task("Native Shell Execution", "Subprocess execution mapped to tool port.", ["Implement adapters/tools/shell.nim"], [us_shell_ast, us_tool_port])

us_web_fetch = add_task("Web Fetch & DOM parse", "Download HTML and convert to clean Markdown.", ["Implement adapters/tools/web_fetch.nim"], [us_sec_ssrf_dns, us_tool_port])
us_browser = add_task("Headless Browser", "Playwright/Puppeteer adapter for JS rendering and screenshots.", ["Implement adapters/tools/browser.nim"], [us_sec_ssrf_dns, us_tool_port])
us_cron = add_task("Cron Scheduled Tasks", "Background task scheduler (nanobot style).", ["Implement core/cron.nim"], [us_tool_port])
us_mcp = add_task("MCP Client Protocol", "Communicate with external Model Context Protocol servers over stdio.", ["Implement adapters/tools/mcp_client.nim"], [us_tool_port])

# ==========================================
# EPIC 7: Ultimate Sandboxing
# ==========================================
us_pad_limits = add_task("Paddock: OS Limits", "Cgroups/rlimit wrappers for CPU/RAM restriction.", ["Implement infra/sandbox/limits.nim"], [us_res])
us_pad_proc = add_task("Paddock: Process Spawn", "Spawn native tools in restricted child processes (moltis style).", ["Implement infra/sandbox/paddock.nim"], [us_pad_limits, us_shell_adap])
us_wasm = add_task("WASM Sandbox", "Wasmtime integration for untrusted plugin execution (ironclaw style).", ["Implement infra/sandbox/wasm.nim"], [us_res])
us_docker = add_task("Docker Ephemeral Sandbox", "Spawn isolated containers for arbitrary Python/Node code (nullclaw).", ["Implement infra/sandbox/docker.nim"], [us_res])

# Generate JSON
prd_json = {
  "name": "Donkey v1.0 \u2014 The Sovereign Architecture (Pipeops Edition)",
  "branchName": "ralph/donkey-v1-sovereign-pipeops",
  "description": "Transcrição profunda das matrizes de paridade, garantindo a topologia pipeops do Donkey: funções unárias, last-arg binding e monadic error handling.",
  "userStories": tasks
}

with open("tasks/prd.json", "w") as f:
    json.dump(prd_json, f, indent=2)

# Generate Markdown
md = "# PRD: Donkey v1.0 — The Sovereign Architecture (Pipeops Edition)\n\n"
md += "## 1. Visão Geral\n"
md += "Este PRD eleva o rigor arquitetural do projeto. O objetivo não é apenas implementar features do ecossistema, mas implementá-las **sob as restrições da topologia `pipeops.nim`** (Inspirado em OCaml/F#). Toda transformação deve ser conectada via `|>` ou `|>->` e toda falha IO encapsulada via `>>=`.\n\n"
md += f"Total de Tarefas Atômicas: **{len(tasks)}**\n\n"

md += "## 2. Quality Gates & Architectural Constraints\n"
md += "**Constraint Primária:** O uso do módulo `src/donkey/core/pipeops.nim` é mandatório.\n"
md += "- `|>`: Pipe forward (ex: `\"hello\" |> strip`). Requer funções unárias.\n"
md += "- `|>->`: Pipe last-arg (ex: `\"world\" |>-> surround(\"hello \")`). Requer target no último argumento.\n"
md += "- `>>=`: Monadic bind (ex: `readFile() >>= parseJson`). Usado para propagar `Result[T, E]` sem blocos `try/except`.\n\n"

md += "Estes comandos são absolutos para validar o CI:\n"
md += "- `nim build src --mm:orc --styleCheck:error --warnings:error` passes\n"
md += "- `testament pattern \"tests/**/*.nim\"` passes\n\n"

md += "## 3. User Stories\n\n"

for t in tasks:
    md += f"### {t['id']}: {t['title']}\n"
    md += f"**Contexto/Descrição:** {t['description']}\n"
    md += f"**Arch Rule:** {t['notes']}\n"
    md += "**Acceptance Criteria:**\n"
    for c in t['acceptanceCriteria']:
        md += f"- [ ] {c}\n"
    md += "\n"

with open("tasks/prd-v1-stable.md", "w") as f:
    f.write(md)

print(f"Generated {len(tasks)} Pipeops-enforced tasks.")
