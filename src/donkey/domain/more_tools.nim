## more_tools.nim — metadata constants for the extended native tool set.
## Pure helpers (calc, globMatch) live in calc.nim.
## Execution lives in app/native_tools.nim.

# ── bash ──────────────────────────────────────────────────────────────────────
const
  BashToolName* = "bash"
  BashToolDescription* =
    "Execute a shell command and return stdout+stderr. " &
    "Use only when the structured fs_, text_, json_, table_, http_fetch, or archive tools do not cover the task. " &
    "Prefer those tools for composable file and data work. " &
    "Use bash for system operations, running scripts, git commands, and build tools. " &
    "Commands run inside the agent paddock when available."
  BashToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"command\":{\"type\":\"string\",\"description\":\"Shell command to run\"}," &
    "\"timeout\":{\"type\":\"integer\",\"description\":\"Timeout in seconds (default 30)\"}" &
    "},\"required\":[\"command\"]}"

# ── read_file ─────────────────────────────────────────────────────────────────
const
  ReadFileToolName* = "read_file"
  ReadFileToolDescription* =
    "Read a local file and return each line prefixed with a stable hashline anchor " &
    "in the form LINE#ID:text. Use this before edit_file. " &
    "The anchors act as both addresses and stale-read checks. " &
    "Local file tools are restricted to the current workspace; use relative paths, `.` or `/workspace`, not `/`. " &
    "`read_file` accesses the same workspace as `bash`, but directly on the host paddock path rather than through the sandbox container."
  ReadFileToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"File path to read\"}," &
    "\"start_line\":{\"type\":\"integer\",\"description\":\"First line number to return (default: 1)\"}," &
    "\"max_lines\":{\"type\":\"integer\",\"description\":\"Maximum lines to return (default: 200)\"}" &
    "},\"required\":[\"path\"]}"

# ── edit_file ─────────────────────────────────────────────────────────────────
const
  EditFileToolName* = "edit_file"
  EditFileToolDescription* =
    "Apply precise in-place file edits using hashline anchors from read_file. " &
    "You must call read_file first and reuse the exact LINE#ID anchors it returned. " &
    "Never invent anchors or substitute plain line numbers/text snippets. " &
    "Supports replace, prepend, and append operations. " &
    "If the file changed since the last read, stale anchors are rejected. " &
    "`edit_file` writes to the same workspace as `bash`; it is not a separate WASM-only filesystem."
  EditFileToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"File path to edit\"}," &
    "\"edits\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{" &
    "\"op\":{\"type\":\"string\",\"enum\":[\"replace\",\"prepend\",\"append\"]}," &
    "\"pos\":{\"type\":\"string\",\"description\":\"Exact LINE#ID anchor returned by read_file for the target line\"}," &
    "\"end\":{\"type\":\"string\",\"description\":\"Exact inclusive end LINE#ID anchor from read_file for replace ranges\"}," &
    "\"lines\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}," &
    "\"description\":\"Literal replacement or inserted lines; empty array deletes for replace\"}" &
    "}},\"description\":\"Edits applied bottom-up\"}" &
    "},\"required\":[\"path\",\"edits\"]}"

# ── find ──────────────────────────────────────────────────────────────────────
const
  FindToolName* = "find"
  FindToolDescription* =
    "Find files or directories by glob pattern. " &
    "Pattern supports * (any sequence) and ? (one char). " &
    "Example: pattern='*.nim', type='file'. " &
    "Search only inside the current workspace; use `.` or `/workspace` for the workspace root, never `/`."
  FindToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"Directory to search inside the current workspace; use . or /workspace for workspace root\"}," &
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
    "For regex, use bash(\"grep -rn 'pattern' /workspace\"). " &
    "Search only inside the current workspace; use relative paths, `.` or `/workspace`, not `/`."
  GrepToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"pattern\":{\"type\":\"string\",\"description\":\"Literal string pattern to search for\"}," &
    "\"path\":{\"type\":\"string\",\"description\":\"File or directory to search inside the current workspace; use . or /workspace for workspace root\"}," &
    "\"recursive\":{\"type\":\"boolean\",\"description\":\"Recurse into subdirectories (default: true)\"}," &
    "\"max\":{\"type\":\"integer\",\"description\":\"Max matches (default: 50)\"}" &
    "},\"required\":[\"pattern\",\"path\"]}"

# ── sed ──────────────────────────────────────────────────────────────────────
const
  SedToolName* = "sed"
  SedToolDescription* =
    "Stream editor for text transformations. " &
    "Supports substitution (s/pattern/replacement/flags), deletion (d), " &
    "print (-n with /pattern/p), and line addressing. " &
    "Runs sandboxed via WASM. Example: expression='s/old/new/g'."
  SedToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"expression\":{\"type\":\"string\",\"description\":\"sed expression (e.g. s/old/new/g, /pattern/d)\"}," &
    "\"path\":{\"type\":\"string\",\"description\":\"File to process\"}" &
    "},\"required\":[\"expression\",\"path\"]}"

# ── wc ────────────────────────────────────────────────────────────────────────
const
  WcToolName* = "wc"
  WcToolDescription* =
    "Count lines, words, and characters in files. " &
    "Runs sandboxed via WASM. Flags: -l (lines), -w (words), -c (chars)."
  WcToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"File to count\"}," &
    "\"flags\":{\"type\":\"string\",\"description\":\"Flags: -l, -w, -c (default: all)\"}" &
    "},\"required\":[\"path\"]}"

# ── head ──────────────────────────────────────────────────────────────────────
const
  HeadToolName* = "head"
  HeadToolDescription* =
    "Return the first N lines of a file. " &
    "Runs sandboxed via WASM."
  HeadToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"File to read\"}," &
    "\"lines\":{\"type\":\"integer\",\"description\":\"Number of lines (default: 10)\"}" &
    "},\"required\":[\"path\"]}"

# ── tail ──────────────────────────────────────────────────────────────────────
const
  TailToolName* = "tail"
  TailToolDescription* =
    "Return the last N lines of a file. " &
    "Runs sandboxed via WASM."
  TailToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"File to read\"}," &
    "\"lines\":{\"type\":\"integer\",\"description\":\"Number of lines (default: 10)\"}" &
    "},\"required\":[\"path\"]}"

# ── sort ──────────────────────────────────────────────────────────────────────
const
  SortToolName* = "sort"
  SortToolDescription* =
    "Sort lines of text. " &
    "Runs sandboxed via WASM. Flags: -r (reverse), -n (numeric), -u (unique)."
  SortToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"File to sort\"}," &
    "\"flags\":{\"type\":\"string\",\"description\":\"Flags: -r, -n, -u, -rn, etc.\"}" &
    "},\"required\":[\"path\"]}"

# ── cp ────────────────────────────────────────────────────────────────────────
const
  CpToolName* = "cp"
  CpToolDescription* =
    "Copy a file. Runs sandboxed via WASM."
  CpToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"source\":{\"type\":\"string\",\"description\":\"Source file path\"}," &
    "\"dest\":{\"type\":\"string\",\"description\":\"Destination file path\"}" &
    "},\"required\":[\"source\",\"dest\"]}"

# ── mv ────────────────────────────────────────────────────────────────────────
const
  MvToolName* = "mv"
  MvToolDescription* =
    "Move or rename a file. Runs sandboxed via WASM."
  MvToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"source\":{\"type\":\"string\",\"description\":\"Source file path\"}," &
    "\"dest\":{\"type\":\"string\",\"description\":\"Destination file path\"}" &
    "},\"required\":[\"source\",\"dest\"]}"

# ── rm ────────────────────────────────────────────────────────────────────────
const
  RmToolName* = "rm"
  RmToolDescription* =
    "Remove a file. Runs sandboxed via WASM."
  RmToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"File to remove\"}" &
    "},\"required\":[\"path\"]}"

# ── mkdir ─────────────────────────────────────────────────────────────────────
const
  MkdirToolName* = "mkdir"
  MkdirToolDescription* =
    "Create a directory. Runs sandboxed via WASM."
  MkdirToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"Directory to create\"}" &
    "},\"required\":[\"path\"]}"

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
    "Returns the model's description or answer to your prompt. " &
    "If prompt is omitted, it asks for a detailed description. " &
    "The path is resolved inside the current workspace like the other local file tools."
  InspectImageToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"Local image file path\"}," &
    "\"prompt\":{\"type\":\"string\"," &
    "\"description\":\"What to analyze (default: describe this image)\"}}" &
    ",\"required\":[\"path\"]}"

# ── structured native tools ──────────────────────────────────────────────────
const
  FsListToolName* = "fs_list"
  FsListToolDescription* =
    "List files or directories as structured JSON records with path, kind, size, and mtime. " &
    "Use this instead of find when you want composable metadata."
  FsListToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"Directory to list inside the current workspace\"}," &
    "\"recursive\":{\"type\":\"boolean\",\"description\":\"Recurse into subdirectories (default: false)\"}," &
    "\"pattern\":{\"type\":\"string\",\"description\":\"Glob pattern filter (default: *)\"}," &
    "\"include_hidden\":{\"type\":\"boolean\",\"description\":\"Include dotfiles and dot-directories (default: false)\"}" &
    "},\"required\":[\"path\"]}"

  FsReadToolName* = "fs_read"
  FsReadToolDescription* =
    "Read a file as structured data. " &
    "Formats: text, lines, json, bytes_meta. " &
    "Use this instead of bash/cat when you need composable output."
  FsReadToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"File path to read inside the current workspace\"}," &
    "\"format\":{\"type\":\"string\",\"enum\":[\"text\",\"lines\",\"json\",\"bytes_meta\"]," &
    "\"description\":\"How to interpret the file contents (default: text)\"}" &
    "},\"required\":[\"path\"]}"

  FsWriteToolName* = "fs_write"
  FsWriteToolDescription* =
    "Write structured content to a file. " &
    "Modes: create, replace, append. " &
    "Formats: text, lines, json."
  FsWriteToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"File path to write inside the current workspace\"}," &
    "\"mode\":{\"type\":\"string\",\"enum\":[\"create\",\"replace\",\"append\"]," &
    "\"description\":\"Write mode (default: replace)\"}," &
    "\"format\":{\"type\":\"string\",\"enum\":[\"text\",\"lines\",\"json\"]," &
    "\"description\":\"How to serialize content (default: text)\"}," &
    "\"content\":{\"description\":\"Structured content payload\"}" &
    "},\"required\":[\"path\",\"content\"]}"

  FsMkdirToolName* = "fs_mkdir"
  FsMkdirToolDescription* =
    "Create a directory inside the current workspace. " &
    "Set parents=true to create intermediate directories."
  FsMkdirToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"Directory path to create\"}," &
    "\"parents\":{\"type\":\"boolean\",\"description\":\"Create intermediate directories (default: false)\"}" &
    "},\"required\":[\"path\"]}"

  FsCopyToolName* = "fs_copy"
  FsCopyToolDescription* =
    "Copy a file or directory tree inside the current workspace. " &
    "Set recursive=true when copying directories."
  FsCopyToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"source\":{\"type\":\"string\",\"description\":\"Source path inside the current workspace\"}," &
    "\"dest\":{\"type\":\"string\",\"description\":\"Destination path inside the current workspace\"}," &
    "\"recursive\":{\"type\":\"boolean\",\"description\":\"Required for directory copies\"}" &
    "},\"required\":[\"source\",\"dest\"]}"

  FsMoveToolName* = "fs_move"
  FsMoveToolDescription* =
    "Move or rename a file or directory inside the current workspace."
  FsMoveToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"source\":{\"type\":\"string\",\"description\":\"Source path inside the current workspace\"}," &
    "\"dest\":{\"type\":\"string\",\"description\":\"Destination path inside the current workspace\"}" &
    "},\"required\":[\"source\",\"dest\"]}"

  FsRemoveToolName* = "fs_remove"
  FsRemoveToolDescription* =
    "Remove a file or directory inside the current workspace. " &
    "Set recursive=true when removing directories."
  FsRemoveToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"Path to remove inside the current workspace\"}," &
    "\"recursive\":{\"type\":\"boolean\",\"description\":\"Required for directory removal\"}" &
    "},\"required\":[\"path\"]}"

  TextSearchToolName* = "text_search"
  TextSearchToolDescription* =
    "Search for a literal string in a file or directory and return structured matches. " &
    "Use this instead of grep when you want composable rows."
  TextSearchToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"pattern\":{\"type\":\"string\",\"description\":\"Literal string pattern to search for\"}," &
    "\"path\":{\"type\":\"string\",\"description\":\"File or directory to search inside the current workspace\"}," &
    "\"recursive\":{\"type\":\"boolean\",\"description\":\"Recurse into subdirectories (default: true)\"}," &
    "\"max\":{\"type\":\"integer\",\"description\":\"Max matches (default: 50)\"}" &
    "},\"required\":[\"pattern\",\"path\"]}"

  TextReadToolName* = "text_read"
  TextReadToolDescription* =
    "Read a slice of text as structured line objects with stable anchors. " &
    "Use this for partial reads and follow-up composition."
  TextReadToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"File path to read\"}," &
    "\"start_line\":{\"type\":\"integer\",\"description\":\"First line to return (default: 1)\"}," &
    "\"max_lines\":{\"type\":\"integer\",\"description\":\"Maximum lines to return (default: 200)\"}" &
    "},\"required\":[\"path\"]}"

  TextReplaceToolName* = "text_replace"
  TextReplaceToolDescription* =
    "Apply a literal text replacement and return a structured summary. " &
    "This is for simple declarative replacements, not regex."
  TextReplaceToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"File path to update\"}," &
    "\"find\":{\"type\":\"string\",\"description\":\"Literal text to find\"}," &
    "\"replace\":{\"type\":\"string\",\"description\":\"Replacement text\"}," &
    "\"count\":{\"type\":\"integer\",\"description\":\"Max replacements; 0 means unlimited\"}" &
    "},\"required\":[\"path\",\"find\"]}"

  JsonQueryToolName* = "json_query"
  JsonQueryToolDescription* =
    "Query or transform JSON with structured operations. " &
    "Supports get, set, delete, and merge."
  JsonQueryToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"op\":{\"type\":\"string\",\"enum\":[\"get\",\"set\",\"delete\",\"merge\"]," &
    "\"description\":\"JSON operation to run\"}," &
    "\"input\":{\"description\":\"Input JSON value\"}," &
    "\"path\":{\"description\":\"Path as string, integer, or array of segments for get/set/delete\"}," &
    "\"value\":{\"description\":\"Replacement value for set\"}," &
    "\"patch\":{\"description\":\"Patch object for merge\"}" &
    "},\"required\":[\"op\",\"input\"]}"

  TableQueryToolName* = "table_query"
  TableQueryToolDescription* =
    "Filter, sort, project, and limit structured row collections. " &
    "Accepts either rows directly or a full structured tool envelope via input."
  TableQueryToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"rows\":{\"type\":\"array\",\"description\":\"Direct row array input\"}," &
    "\"input\":{\"description\":\"Structured tool envelope or raw object/array containing rows\"}," &
    "\"rows_path\":{\"description\":\"Optional explicit path to the row array inside input\"}," &
    "\"where\":{\"type\":\"array\",\"description\":\"Filter clauses with field, op, and value\"}," &
    "\"select\":{\"type\":\"array\",\"description\":\"Fields or field paths to project\"}," &
    "\"sort\":{\"type\":\"array\",\"description\":\"Sort specs with field and order\"}," &
    "\"limit\":{\"type\":\"integer\",\"description\":\"Maximum number of output rows\"}" &
    "},\"required\":[]}"

  HttpFetchToolName* = "http_fetch"
  HttpFetchToolDescription* =
    "Fetch a URL and return structured HTTP data including status and parsed body. " &
    "Respects the same public-URL restrictions as fetch."
  HttpFetchToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"url\":{\"type\":\"string\",\"description\":\"Public URL to fetch\"}," &
    "\"expect\":{\"type\":\"string\",\"enum\":[\"text\",\"json\"]," &
    "\"description\":\"Expected body format (default: text)\"}," &
    "\"max_chars\":{\"type\":\"integer\",\"description\":\"Max characters to keep for text responses\"}" &
    "},\"required\":[\"url\"]}"

  ArchiveExtractToolName* = "archive_extract"
  ArchiveExtractToolDescription* =
    "Extract a zip or tar archive into a destination directory inside the current workspace."
  ArchiveExtractToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"archive_path\":{\"type\":\"string\",\"description\":\"Archive path inside the current workspace\"}," &
    "\"destination\":{\"type\":\"string\",\"description\":\"Destination directory inside the current workspace\"}" &
    "},\"required\":[\"archive_path\",\"destination\"]}"

  ArchiveCreateToolName* = "archive_create"
  ArchiveCreateToolDescription* =
    "Create a zip or tar archive from files or directories inside the current workspace."
  ArchiveCreateToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"archive_path\":{\"type\":\"string\",\"description\":\"Archive output path inside the current workspace\"}," &
    "\"inputs\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}," &
    "\"description\":\"Files or directories to include\"}" &
    "},\"required\":[\"archive_path\",\"inputs\"]}"

# ── ask ───────────────────────────────────────────────────────────────────────
const
  AskToolName* = "ask"
  AskToolDescription* =
    "Ask the user a clarifying question and wait for their reply. " &
    "Use when you need information that isn't available from context. " &
    "Returns the user's exact response text, or an interruption error if the session is rebuilt."
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

# ── manage_skills ─────────────────────────────────────────────────────────────
const
  ManageSkillsToolName* = "manage_skills"
  ManageSkillsToolDescription* =
    "Search the remote skill registry, install remote bundles, enable/disable skills, " &
    "or read the SKILL.md content of any installed remote skill bundle. " &
    "Use this when you need a capability not already available, " &
    "or when the user asks how to install or enable a skill, " &
    "or when you want to read the content of a skill's SKILL.md."
  ManageSkillsToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"action\":{\"type\":\"string\",\"enum\":[\"help\",\"list\",\"search\",\"install\",\"enable\",\"disable\",\"read\"]," &
    "\"description\":\"Skill management action\"}," &
    "\"query\":{\"type\":\"string\",\"description\":\"Search query for action=search\"}," &
    "\"slug\":{\"type\":\"string\",\"description\":\"Bundle slug for install/enable/read\"}," &
    "\"name\":{\"type\":\"string\",\"description\":\"Enabled skill name for action=disable\"}," &
    "\"registry\":{\"type\":\"string\",\"description\":\"Optional registry override\"}" &
    "}}"

# ── task ──────────────────────────────────────────────────────────────────────
const
  TaskToolName* = "task"
  TaskToolDescription* =
    "Start a focused background subtask using the active AI model. " &
    "Returns a job_id immediately; use await to collect results and cancel_job to stop it. " &
    "Use for independent research or analysis that can run separately from the current turn."
  TaskToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"prompt\":{\"type\":\"string\",\"description\":\"Task for the model to complete\"}," &
    "\"context\":{\"type\":\"string\",\"description\":\"Additional context for the model\"}}" &
    ",\"required\":[\"prompt\"]}"

# ── submit_result ─────────────────────────────────────────────────────────────
const
  SubmitResultToolName* = "submit_result"
  SubmitResultToolDescription* =
    "Submit the final result of a background or delegated task. " &
    "In the current single-agent runtime, returns the result verbatim."
  SubmitResultToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"result\":{\"type\":\"string\",\"description\":\"Final result to submit\"}}" &
    ",\"required\":[\"result\"]}"

# ── report_finding ────────────────────────────────────────────────────────────
const
  ReportFindingToolName* = "report_finding"
  ReportFindingToolDescription* =
    "Report an intermediate finding during a background or delegated task. " &
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
    "Cancel a background job created by task using its job_id."
  CancelJobToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"job_id\":{\"type\":\"string\",\"description\":\"Job ID to cancel\"}}" &
    ",\"required\":[\"job_id\"]}"

# ── await ─────────────────────────────────────────────────────────────────────
const
  AwaitToolName* = "await"
  AwaitToolDescription* =
    "Wait for one or more background jobs created by task and return lines in the form job_id: result."
  AwaitToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"job_ids\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}," &
    "\"description\":\"Job IDs to wait for\"}}" &
    ",\"required\":[\"job_ids\"]}"

# ── execute_code ──────────────────────────────────────────────────────────────
const
  ExecuteCodeToolName* = "execute_code"
  ExecuteCodeToolDescription* =
    "Run a short Python, JavaScript, shell or WASI program inside an isolated sandbox. " &
    "Network is disabled, the workspace is the only writable mount, output is capped and the " &
    "run is killed on timeout. Requires sandbox.mode='oci' (python/javascript/shell) or " &
    "sandbox.mode='wasm' (language='wasm'). This tool is approval-gated by default."
  ExecuteCodeToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"language\":{\"type\":\"string\",\"enum\":[\"python\",\"javascript\",\"shell\",\"wasm\"]," &
    "\"description\":\"Runtime to execute\"}," &
    "\"code\":{\"type\":\"string\",\"description\":\"Source code (not used for wasm)\"}," &
    "\"wasm_path\":{\"type\":\"string\",\"description\":\"Path to a .wasm module inside the workspace (wasm only)\"}," &
    "\"timeout_sec\":{\"type\":\"integer\",\"description\":\"Wall-clock timeout in seconds (default: 10, max: 60)\"}" &
    "},\"required\":[\"language\"]}"
