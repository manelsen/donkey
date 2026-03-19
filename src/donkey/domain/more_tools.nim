## more_tools.nim — metadata constants for the extended native tool set.
## Pure helpers (calc, globMatch) live in calc.nim.
## Execution lives in app/native_tools.nim.

# ── bash ──────────────────────────────────────────────────────────────────────
const
  BashToolName* = "bash"
  BashToolDescription* =
    "Execute a shell command and return stdout+stderr. " &
    "Use for system operations, running scripts, git commands, build tools. " &
    "Working directory is the server's CWD."
  BashToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"command\":{\"type\":\"string\",\"description\":\"Shell command to run\"}," &
    "\"timeout\":{\"type\":\"integer\",\"description\":\"Timeout in seconds (default 30)\"}" &
    "},\"required\":[\"command\"]}"

# ── hashline ──────────────────────────────────────────────────────────────────
const
  HashlineToolName* = "hashline"
  HashlineToolDescription* =
    "Compute SHA-256 hash of a string or file. " &
    "Provide 'input' for a string, 'file' for a file path, or 'file'+'line' " &
    "for a specific line number. Returns lowercase hex digest."
  HashlineToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"input\":{\"type\":\"string\",\"description\":\"String to hash\"}," &
    "\"file\":{\"type\":\"string\",\"description\":\"File path to hash\"}," &
    "\"line\":{\"type\":\"integer\",\"description\":\"Hash a specific line (1-indexed, requires file)\"}" &
    "}}"

# ── find ──────────────────────────────────────────────────────────────────────
const
  FindToolName* = "find"
  FindToolDescription* =
    "Find files or directories by glob pattern. " &
    "Pattern supports * (any sequence) and ? (one char). " &
    "Example: pattern='*.nim', type='file'."
  FindToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"Directory to search\"}," &
    "\"pattern\":{\"type\":\"string\",\"description\":\"Glob pattern (default: *)\"}," &
    "\"type\":{\"type\":\"string\",\"enum\":[\"file\",\"dir\",\"any\"]," &
    "\"description\":\"Filter by type (default: file)\"}," &
    "\"max\":{\"type\":\"integer\",\"description\":\"Max results (default: 50)\"}" &
    "},\"required\":[\"path\"]}"

# ── grep ──────────────────────────────────────────────────────────────────────
const
  GrepToolName* = "grep"
  GrepToolDescription* =
    "Search file contents for a literal string pattern. " &
    "Returns matching lines as 'file:linenum:content'. " &
    "Recursively searches directories by default. " &
    "For regex, use bash(\"grep -rn 'pattern' /path\")."
  GrepToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"pattern\":{\"type\":\"string\",\"description\":\"Regex pattern\"}," &
    "\"path\":{\"type\":\"string\",\"description\":\"File or directory to search\"}," &
    "\"recursive\":{\"type\":\"boolean\",\"description\":\"Recurse into subdirectories (default: true)\"}," &
    "\"max\":{\"type\":\"integer\",\"description\":\"Max matches (default: 50)\"}" &
    "},\"required\":[\"pattern\",\"path\"]}"

# ── fetch ─────────────────────────────────────────────────────────────────────
const
  FetchToolName* = "fetch"
  FetchToolDescription* =
    "Fetch a URL and return cleaned text content. " &
    "HTML tags are stripped, JSON is pretty-printed. " &
    "Does not allow private/internal addresses."
  FetchToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"url\":{\"type\":\"string\",\"description\":\"URL to fetch\"}," &
    "\"max_chars\":{\"type\":\"integer\"," &
    "\"description\":\"Max characters to return (default: 5000, hard cap: 20000)\"}" &
    "},\"required\":[\"url\"]}"

# ── web_search ────────────────────────────────────────────────────────────────
const
  WebSearchToolName* = "web_search"
  WebSearchToolDescription* =
    "Search the web using Brave Search API. " &
    "Returns titles, URLs, and descriptions for the top results. " &
    "Requires BRAVE_API_KEY environment variable."
  WebSearchToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"query\":{\"type\":\"string\",\"description\":\"Search query\"}," &
    "\"count\":{\"type\":\"integer\"," &
    "\"description\":\"Number of results (default: 5, max: 20)\"}" &
    "},\"required\":[\"query\"]}"

# ── calc ──────────────────────────────────────────────────────────────────────
const
  CalcToolName* = "calc"
  CalcToolDescription* =
    "Evaluate a math expression. " &
    "Supports +, -, *, /, % (modulo), ** (power), parentheses, unary ±. " &
    "Literals: decimal, 0xFF hex, 0b binary, 0o octal."
  CalcToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"expression\":{\"type\":\"string\"," &
    "\"description\":\"Math expression to evaluate\"}},\"required\":[\"expression\"]}"

# ── render_mermaid ────────────────────────────────────────────────────────────
const
  RenderMermaidToolName* = "render_mermaid"
  RenderMermaidToolDescription* =
    "Render a Mermaid diagram. " &
    "If mmdc (Mermaid CLI) is installed, generates an SVG file and returns its path. " &
    "Otherwise returns the source formatted for display."
  RenderMermaidToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"diagram\":{\"type\":\"string\",\"description\":\"Mermaid diagram source\"}}" &
    ",\"required\":[\"diagram\"]}"

# ── inspect_image ─────────────────────────────────────────────────────────────
const
  InspectImageToolName* = "inspect_image"
  InspectImageToolDescription* =
    "Analyze a local image file using a vision-capable AI model. " &
    "Reads the file, encodes it, and sends it to the active provider. " &
    "Returns the model's description or answer to your prompt."
  InspectImageToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"Local image file path\"}," &
    "\"prompt\":{\"type\":\"string\"," &
    "\"description\":\"What to analyze (default: describe this image)\"}}" &
    ",\"required\":[\"path\"]}"

# ── ask ───────────────────────────────────────────────────────────────────────
const
  AskToolName* = "ask"
  AskToolDescription* =
    "Ask the user a clarifying question and wait for their reply. " &
    "Use when you need information that isn't available from context. " &
    "Returns the user's exact response text."
  AskToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"question\":{\"type\":\"string\",\"description\":\"Question to ask the user\"}}" &
    ",\"required\":[\"question\"]}"

# ── todo_write ────────────────────────────────────────────────────────────────
const
  TodoWriteToolName* = "todo_write"
  TodoWriteToolDescription* =
    "Manage a session todo list. " &
    "ops: array of {op, id?, title?, phase?, notes?}. " &
    "op: 'create' | 'update' | 'delete'. " &
    "phase: 'backlog' | 'in_progress' | 'completed'. " &
    "Returns the full current todo list after applying ops."
  TodoWriteToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"ops\":{\"type\":\"array\",\"items\":{\"type\":\"object\"," &
    "\"properties\":{" &
    "\"op\":{\"type\":\"string\",\"enum\":[\"create\",\"update\",\"delete\"]}," &
    "\"id\":{\"type\":\"string\"}," &
    "\"title\":{\"type\":\"string\"}," &
    "\"phase\":{\"type\":\"string\",\"enum\":[\"backlog\",\"in_progress\",\"completed\"]}," &
    "\"notes\":{\"type\":\"string\"}" &
    "}}}},\"required\":[\"ops\"]}"

# ── checkpoint ────────────────────────────────────────────────────────────────
const
  CheckpointToolName* = "checkpoint"
  CheckpointToolDescription* =
    "Save a snapshot of the current conversation history. " &
    "Use before exploratory or destructive operations. " &
    "Returns the checkpoint index for later use with rewind."
  CheckpointToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"label\":{\"type\":\"string\",\"description\":\"Optional label for this checkpoint\"}}}"

# ── rewind ────────────────────────────────────────────────────────────────────
const
  RewindToolName* = "rewind"
  RewindToolDescription* =
    "Restore conversation history to a previously saved checkpoint. " &
    "Discards all history after the checkpoint. " &
    "Use checkpoint index from the checkpoint tool output."
  RewindToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"index\":{\"type\":\"integer\"," &
    "\"description\":\"Checkpoint index (default: last checkpoint)\"}}}"

# ── task ──────────────────────────────────────────────────────────────────────
const
  TaskToolName* = "task"
  TaskToolDescription* =
    "Run a focused subtask using the AI model. " &
    "The model receives the prompt (plus optional context) and returns its response. " &
    "Use to parallelize independent research or analysis."
  TaskToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"prompt\":{\"type\":\"string\",\"description\":\"Task for the model to complete\"}," &
    "\"context\":{\"type\":\"string\",\"description\":\"Additional context for the model\"}}" &
    ",\"required\":[\"prompt\"]}"

# ── submit_result ─────────────────────────────────────────────────────────────
const
  SubmitResultToolName* = "submit_result"
  SubmitResultToolDescription* =
    "Submit the final result of a task (for use by subagents). " &
    "In single-agent context, returns the result verbatim."
  SubmitResultToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"result\":{\"type\":\"string\",\"description\":\"Final result to submit\"}}" &
    ",\"required\":[\"result\"]}"

# ── report_finding ────────────────────────────────────────────────────────────
const
  ReportFindingToolName* = "report_finding"
  ReportFindingToolDescription* =
    "Report an intermediate finding during a task. " &
    "Used to surface partial results without ending the task. " &
    "Returns the finding acknowledged."
  ReportFindingToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"finding\":{\"type\":\"string\",\"description\":\"Intermediate finding to report\"}}" &
    ",\"required\":[\"finding\"]}"

# ── cancel_job ────────────────────────────────────────────────────────────────
const
  CancelJobToolName* = "cancel_job"
  CancelJobToolDescription* =
    "Cancel a running background job created by the task tool."
  CancelJobToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"job_id\":{\"type\":\"string\",\"description\":\"Job ID to cancel\"}}" &
    ",\"required\":[\"job_id\"]}"

# ── await ─────────────────────────────────────────────────────────────────────
const
  AwaitToolName* = "await"
  AwaitToolDescription* =
    "Wait for one or more background jobs to complete and return their results."
  AwaitToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"job_ids\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}," &
    "\"description\":\"Job IDs to wait for\"}}" &
    ",\"required\":[\"job_ids\"]}"
