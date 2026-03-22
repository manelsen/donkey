import json

tasks = []
task_id = 1

def add_task(title, desc, criteria, deps):
    global task_id
    id_str = f"US-{task_id:03d}"
    tasks.append({
        "id": id_str,
        "title": title,
        "description": desc,
        "acceptanceCriteria": criteria + [
            "nim build src --mm:orc --styleCheck:error --warnings:error passes",
            "testament pattern 'tests/**/*.nim' passes"
        ],
        "priority": task_id,
        "passes": False,
        "notes": "",
        "dependsOn": deps
    })
    task_id += 1
    return id_str

# Phase 1: Hardening & Core Types
us_flags = add_task("Compiler Strict Mode", "Enable strict compilation flags globally.", ["Update config.nims to include --styleCheck:error, --warnings:error, --panics:on"], [])
us_fix = add_task("Fix Existing Style Warnings", "Resolve all current compiler warnings.", ["Codebase compiles cleanly with strict flags"], [us_flags])
us_res = add_task("Core Result[T, E] Type", "Implement or import a robust Result type for error handling.", ["Create or define Result type in core/types.nim"], [us_fix])
us_io = add_task("Safe IO Wrapper", "Wrap std/sys file ops to return Result instead of exceptions.", ["Create core/safe_io.nim", "Implement safeReadFile, safeWriteFile"], [us_res])

# Phase 2: LLM Providers (OpenAI)
us_http = add_task("Safe HTTP Client", "Wrap std/httpclient to return Result.", ["Create core/safe_http.nim", "Implement safeGet, safePost"], [us_io])
us_oai_auth = add_task("OpenAI Auth Builder", "Pure function to build OpenAI auth headers.", ["Create domain/providers/openai_pure.nim", "Implement buildHeaders(key)"], [us_http])
us_oai_chat = add_task("OpenAI Chat Request Builder", "Pure function to format OpenAI chat payload.", ["Implement buildChatPayload(messages) in openai_pure.nim"], [us_oai_auth])
us_oai_parse = add_task("OpenAI Response Parser", "Pure function to parse OpenAI JSON response.", ["Implement parseChatResponse(json) in openai_pure.nim"], [us_oai_chat])
us_oai_tool = add_task("OpenAI Tool Format", "Pure function to format Nim tool schemas to OpenAI JSON.", ["Implement formatTools(tools) in openai_pure.nim"], [us_oai_parse])
us_oai_adap = add_task("OpenAI IO Adapter", "Integrate pure functions with HTTP client.", ["Create adapters/providers/openai_adapter.nim", "Implement generateCompletion()"], [us_oai_tool])

# Phase 3: LLM Providers (Ollama)
us_oll_auth = add_task("Ollama Auth/Config", "Pure function for Ollama connection setup.", ["Create domain/providers/ollama_pure.nim", "Implement buildEndpoint(host, port)"], [us_http])
us_oll_chat = add_task("Ollama Chat Request", "Pure function to format Ollama payload.", ["Implement buildChatPayload(messages) in ollama_pure.nim"], [us_oll_auth])
us_oll_parse = add_task("Ollama Response Parser", "Pure function to parse Ollama response.", ["Implement parseChatResponse(json) in ollama_pure.nim"], [us_oll_chat])
us_oll_adap = add_task("Ollama IO Adapter", "Integrate Ollama pure functions with HTTP.", ["Create adapters/providers/ollama_adapter.nim", "Implement generateCompletion()"], [us_oll_parse])

# Phase 4: Routing & Failover
us_route_types = add_task("Router Types", "Define routing and failover policies.", ["Create domain/routing/types.nim", "Define Policy enum and ProviderTier"], [us_res])
us_route_logic = add_task("Smart Routing Logic", "Pure function to select provider based on task complexity.", ["Create domain/routing/selector.nim", "Implement selectProvider(task, policies)"], [us_route_types])
us_retry_state = add_task("Retry State Machine", "Pure logic to handle provider fallbacks.", ["Create domain/routing/retry.nim", "Implement nextAction(error, attempts)"], [us_route_logic])

# Phase 5: Local Storage (SQLite)
us_db_port = add_task("Storage Port", "Define storage interface.", ["Create ports/storage.nim", "Define DbPort interface"], [us_res])
us_sq_conn = add_task("SQLite Connection", "Safe SQLite connection wrapper.", ["Create adapters/storage/sqlite_adapter.nim", "Implement connect() returning Result"], [us_db_port])
us_sq_schema = add_task("SQLite Schema init", "Create sessions and messages tables.", ["Implement initSchema() in sqlite_adapter.nim"], [us_sq_conn])
us_sq_insert = add_task("SQLite Insert Message", "Implement message persistence.", ["Implement saveMessage() in sqlite_adapter.nim"], [us_sq_schema])
us_sq_query = add_task("SQLite Query History", "Implement message retrieval.", ["Implement getSessionHistory() in sqlite_adapter.nim"], [us_sq_insert])

# Phase 6: Vector Storage (pgvector)
us_pg_conn = add_task("Postgres Connection", "Safe Postgres connection via db_postgres.", ["Create adapters/storage/postgres_adapter.nim"], [us_db_port])
us_pg_schema = add_task("pgvector Schema", "Create tables with vector columns.", ["Implement initVectorSchema() in postgres_adapter.nim"], [us_pg_conn])
us_chunk_pure = add_task("Text Chunking Logic", "Pure function to split text.", ["Create domain/memory/chunker.nim", "Implement splitByTokens(text, max)"], [us_res])
us_emb_oai = add_task("OpenAI Embedding Fetch", "Adapter to fetch embeddings.", ["Implement fetchEmbedding() in openai_adapter.nim"], [us_oai_adap])
us_pg_insert = add_task("pgvector Insert", "Insert text and vector to DB.", ["Implement saveEmbedding() in postgres_adapter.nim"], [us_pg_schema, us_emb_oai])
us_pg_cosine = add_task("Cosine Similarity Query", "Query DB using <-> operator.", ["Implement searchSimilar() in postgres_adapter.nim"], [us_pg_insert])
us_rrf_logic = add_task("Reciprocal Rank Fusion", "Pure function to combine search results.", ["Create domain/memory/rrf.nim", "Implement mergeResults(bm25, vector)"], [us_chunk_pure])

# Phase 7: Security (Secret Scanning)
us_sec_regex = add_task("Secret Regex Patterns", "Pure module with regex for known keys.", ["Create domain/security/secrets.nim", "Define patterns for AWS, API keys"], [us_res])
us_sec_shannon = add_task("Shannon Entropy Calc", "Pure function to detect high-entropy strings.", ["Implement calculateEntropy(string) in secrets.nim"], [us_sec_regex])
us_sec_scrub = add_task("Text Scrubber", "Pure function to replace secrets with asterisks.", ["Implement scrubText(text) in secrets.nim"], [us_sec_shannon])
us_sec_mid = add_task("Tool Output Middleware", "Apply scrubber to tool outputs in orchestrator.", ["Update orchestrator to call scrubText before logging/returning"], [us_sec_scrub])

# Phase 8: Security (SSRF)
us_ssrf_ip = add_task("IP Parser", "Pure function to parse and validate IP addresses.", ["Create domain/security/network.nim", "Implement isPrivateIp(ip)"], [us_res])
us_ssrf_url = add_task("URL Host Extractor", "Pure function to extract host from URL.", ["Implement extractHost(url) in network.nim"], [us_ssrf_ip])
us_ssrf_dns = add_task("Safe DNS Resolution", "Adapter to resolve host and check against SSRF rules.", ["Create adapters/security/dns.nim", "Implement safeResolve(host)"], [us_ssrf_url])

# Phase 9: Native Tools (Shell & FS)
us_sh_ast = add_task("Shell Command AST", "Pure parser to detect shell operators.", ["Create domain/tools/shell_parser.nim", "Implement isSafeCommand(cmd)"], [us_res])
us_sh_allow = add_task("Shell Allowlist", "Define permitted binaries (ls, cat, etc).", ["Implement checkAllowlist(cmd) in shell_parser.nim"], [us_sh_ast])
us_sh_exec = add_task("Subprocess Exec", "Safe wrapper around osproc.", ["Create adapters/tools/shell_adapter.nim", "Implement runCommand()"], [us_sh_allow])
us_fs_path = add_task("Path Sandbox", "Pure function to prevent path traversal (../).", ["Create domain/tools/fs_sandbox.nim", "Implement isPathInsideWorkspace(path)"], [us_res])
us_fs_read = add_task("FS Read Tool", "Native tool to read files.", ["Create adapters/tools/fs_tools.nim", "Implement read_file tool using safe_io"], [us_fs_path, us_io])
us_fs_write = add_task("FS Write Tool", "Native tool to write files.", ["Implement write_file tool using safe_io"], [us_fs_path, us_io])

# Phase 10: Sandboxing (Paddock)
us_pad_limits = add_task("OS Limits Wrapper", "Wrapper for setrlimit (Linux/Unix).", ["Create infra/sandbox/limits.nim", "Implement setCpuLimit(), setMemLimit()"], [us_res])
us_pad_proc = add_task("Paddock Process Spawn", "Spawn tool adapter as a restricted child process.", ["Create infra/sandbox/paddock.nim", "Implement spawnRestricted()"], [us_pad_limits, us_sh_exec])
us_pad_ipc = add_task("Paddock IPC", "Communicate with sandboxed tool via stdin/stdout JSON.", ["Implement ipcSend(), ipcReceive() in paddock.nim"], [us_pad_proc])

# Phase 11: Ingress Channels
us_ch_port = add_task("Ingress Port", "Define Ingress Channel interface.", ["Create ports/ingress.nim", "Define ChannelPort interface"], [us_res])
us_cli_repl = add_task("CLI REPL Channel", "Terminal loop for agent interaction.", ["Create adapters/channels/cli_repl.nim"], [us_ch_port])
us_slk_parse = add_task("Slack Event Parser", "Pure function to parse Slack JSON payload.", ["Create domain/channels/slack_pure.nim", "Implement parseEvent(json)"], [us_ch_port])
us_slk_adap = add_task("Slack Webhook Adapter", "HTTP handler for Slack events.", ["Create adapters/channels/slack_webhook.nim"], [us_slk_parse])
us_wa_parse = add_task("WhatsApp Payload Parser", "Pure function to parse WA messages.", ["Create domain/channels/whatsapp_pure.nim", "Implement parseMessage(json)"], [us_ch_port])
us_wa_adap = add_task("WhatsApp Webhook Adapter", "HTTP handler for WhatsApp.", ["Create adapters/channels/whatsapp_webhook.nim"], [us_wa_parse])

# Generate JSON
prd_json = {
  "name": "Donkey v1.0 — Paridade Integral (Atomic Tasks)",
  "branchName": "ralph/donkey-v1-atomic",
  "description": "Especificação granular em nivel de unidade (funções puras, adaptadores isolados) para atingir paridade funcional total.",
  "userStories": tasks
}

with open("tasks/prd.json", "w") as f:
    json.dump(prd_json, f, indent=2)

# Generate Markdown
md = "# PRD: Donkey v1.0 — Paridade Integral (Atomic Tasks)\n\n"
md += "## 1. Visão Geral\nUm PRD hiper-granular contendo " + str(len(tasks)) + " tarefas atômicas, desenhadas para execução autônoma via AI agents. Cobre refatoração de core, providers LLM, memória vetorial, segurança, ferramentas nativas e canais de comunicação.\n\n"
md += "## 2. Quality Gates\n- `nim build src --mm:orc --styleCheck:error --warnings:error` passes\n- `testament pattern \"tests/**/*.nim\"` passes\n\n"
md += "## 3. User Stories\n\n"

for t in tasks:
    md += f"### {t['id']}: {t['title']}\n"
    md += f"**Description:** {t['description']}\n"
    md += "**Acceptance Criteria:**\n"
    for c in t['acceptanceCriteria']:
        md += f"- [ ] {c}\n"
    md += "\n"

with open("tasks/prd-v1-stable.md", "w") as f:
    f.write(md)

print(f"Generated {len(tasks)} tasks.")
