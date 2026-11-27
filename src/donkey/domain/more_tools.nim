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
# ── transcribe_audio ───────────────────────────────────────────────────────────
const
  TranscribeAudioToolName* = "transcribe_audio"
  TranscribeAudioToolDescription* =
    "Transcribe a local audio file with the configured speech-to-text endpoint. " &
    "Accepts mp3, ogg/opus, wav, m4a, webm and flac. " &
    "The path is resolved inside the current workspace like the other local file tools."
  TranscribeAudioToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"Local audio file path\"}," &
    "\"language\":{\"type\":\"string\",\"description\":\"Optional ISO language hint\"}," &
    "\"prompt\":{\"type\":\"string\",\"description\":\"Optional vocabulary/context hint\"}}" &
    ",\"required\":[\"path\"]}"

# ── send_file ──────────────────────────────────────────────────────────────────
const
  SendFileToolName* = "send_file"
  SendFileToolDescription* =
    "Send a file from the workspace to the person, in this conversation " &
    "(a report you wrote, an attachment they sent, a generated chart). The " &
    "path is resolved inside the current workspace like the other local file " &
    "tools. On a channel that cannot receive files the tool says so: then tell " &
    "the person where the file is saved."
  SendFileToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"Workspace path of the file\"}," &
    "\"caption\":{\"type\":\"string\",\"description\":\"Optional text sent with the file\"}}" &
    ",\"required\":[\"path\"]}"

# ── editor_read_file (E10.5) ───────────────────────────────────────────────────
const
  EditorReadFileToolName* = "editor_read_file"
  EditorReadFileToolDescription* =
    "Read a text file in the person's editor (Zed and others, through donkey " &
    "acp), from the project they have open there, including unsaved changes. " &
    "Only works when the person is talking to you from an editor; elsewhere " &
    "it says so. A relative path is resolved from the project's folder. Asks " &
    "the person's approval. Use line and limit for a part of a long file."
  EditorReadFileToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"File path, absolute or relative to the editor's project\"}," &
    "\"line\":{\"type\":\"integer\",\"description\":\"Optional first line (1-based)\"}," &
    "\"limit\":{\"type\":\"integer\",\"description\":\"Optional number of lines\"}}" &
    ",\"required\":[\"path\"]}"

# ── text_to_speech ─────────────────────────────────────────────────────────────
const
  TextToSpeechToolName* = "text_to_speech"
  TextToSpeechToolDescription* =
    "Synthesize speech from text with the configured text-to-speech endpoint. " &
    "Writes the audio under the workspace attachments and returns its path. " &
    "With as_voice=true the speech is also delivered to the channel as a voice " &
    "note when the channel supports voice (Telegram); otherwise the audio is " &
    "only saved."
  TextToSpeechToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"text\":{\"type\":\"string\",\"description\":\"Text to speak\"}," &
    "\"voice\":{\"type\":\"string\",\"description\":\"Optional voice name\"}," &
    "\"format\":{\"type\":\"string\",\"description\":\"mp3 (default), opus, wav, aac or flac\"}," &
    "\"as_voice\":{\"type\":\"boolean\",\"description\":\"Deliver the speech as a voice note in the channel when it supports voice (default: false)\"}," &
    "\"caption\":{\"type\":\"string\",\"description\":\"Caption sent with the voice note\"}}" &
    ",\"required\":[\"text\"]}"

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

# ── manage_agents ─────────────────────────────────────────────────────────────
const
  ManageAgentsToolName* = "manage_agents"
  ManageAgentsToolDescription* =
    "Create, list, change or delete the user's named agents, and add to an " &
    "agent's own notes. A named agent is a persona the user calls by starting " &
    "a message with @name: it shares the user's memory and this conversation, " &
    "has its own role (the description) and optionally its own provider/model. " &
    "Use it when the user asks for a specialist ('create a reviewer that...'), " &
    "and with action=note when, as a named agent, you want to remember something " &
    "for your next turns."
  ManageAgentsToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"action\":{\"type\":\"string\",\"enum\":[\"list\",\"create\",\"update\",\"delete\",\"note\"]}," &
    "\"name\":{\"type\":\"string\",\"description\":\"Agent name: 1-32 of a-z, 0-9, '-'\"}," &
    "\"description\":{\"type\":\"string\",\"description\":\"The agent's role and persona\"}," &
    "\"provider\":{\"type\":\"string\",\"description\":\"Optional provider id\"}," &
    "\"model\":{\"type\":\"string\",\"description\":\"Optional model id\"}," &
    "\"text\":{\"type\":\"string\",\"description\":\"Note to append for action=note\"}" &
    "},\"required\":[\"action\"]}"

# ── manage_tasks ──────────────────────────────────────────────────────────────
const
  ManageTasksToolName* = "manage_tasks"
  ManageTasksToolDescription* =
    "The user's task board, shared with their named agents: add a task, move " &
    "it (todo, doing, blocked, done), assign it to the user (empty) or to an " &
    "agent (@name), add a note, set a due date (YYYY-MM-DD), delete it, or " &
    "list the board (optionally by state or assignee). Use it for work that " &
    "spans conversations ('remind me what is pending', 'put this on my " &
    "list'); for the steps of the current answer use todo_write instead. " &
    "Tasks are t1, t2, …; at most 200."
  ManageTasksToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"action\":{\"type\":\"string\",\"enum\":[\"list\",\"add\",\"move\",\"assign\",\"note\",\"due\",\"delete\"]}," &
    "\"id\":{\"type\":\"string\",\"description\":\"Task id, e.g. t3\"}," &
    "\"title\":{\"type\":\"string\",\"description\":\"What is to be done (add)\"}," &
    "\"state\":{\"type\":\"string\",\"enum\":[\"todo\",\"doing\",\"blocked\",\"done\"],\"description\":\"move: the new state; list: only this state\"}," &
    "\"assignee\":{\"type\":\"string\",\"description\":\"Empty for the user, @name for an agent; list: only theirs\"}," &
    "\"due\":{\"type\":\"string\",\"description\":\"YYYY-MM-DD, or empty to clear\"}," &
    "\"text\":{\"type\":\"string\",\"description\":\"The note (note)\"}" &
    "},\"required\":[\"action\"]}"

# ── manage_schedules ──────────────────────────────────────────────────────────
const
  ManageSchedulesToolName* = "manage_schedules"
  ManageSchedulesToolDescription* =
    "Create, list, pause, resume or delete the user's recurring jobs. At each " &
    "run the prompt is given to you as a task in this channel, with your tools, " &
    "and your answer goes to the user: use it for 'every weekday at 9 send me " &
    "the news', 'check the build every 2 hours'. For a one-time reminder use " &
    "schedule_reminder instead. `schedule` is a 5-field cron (minute hour " &
    "day month weekday, '0 9 * * 1-5'), @hourly, @daily, @weekly, @monthly, " &
    "or '@every 30m' (m/h/d, counted from now). A cron runs on the clock of " &
    "`timezone` (UTC±HH:MM, the user's offset; default UTC). At most one run " &
    "every 5 minutes, 20 jobs per user."
  ManageSchedulesToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"action\":{\"type\":\"string\",\"enum\":[\"list\",\"create\",\"delete\",\"pause\",\"resume\"]}," &
    "\"name\":{\"type\":\"string\",\"description\":\"Job name: 1-32 of a-z, 0-9, '-'\"}," &
    "\"schedule\":{\"type\":\"string\",\"description\":\"Cron, alias or @every <n><m|h|d>\"}," &
    "\"prompt\":{\"type\":\"string\",\"description\":\"What to do at each run, written as a task for yourself\"}," &
    "\"timezone\":{\"type\":\"string\",\"description\":\"UTC±HH:MM for a cron; default UTC+00:00\"}," &
    "\"catch_up\":{\"type\":\"string\",\"enum\":[\"skip\",\"once\"],\"description\":\"After downtime: skip missed runs (default) or run the latest once\"}" &
    "},\"required\":[\"action\"]}"

# ── ask_agent / convene_agents ────────────────────────────────────────────────
const
  AskAgentToolName* = "ask_agent"
  AskAgentToolDescription* =
    "Ask one of the user's named agents a question and get its answer back. " &
    "The agent answers with its own role, notes and model, in one reply, " &
    "without tools. Put what it needs to know in `context`: it does not see " &
    "this turn."
  AskAgentToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"name\":{\"type\":\"string\",\"description\":\"The agent's name\"}," &
    "\"question\":{\"type\":\"string\"}," &
    "\"context\":{\"type\":\"string\",\"description\":\"What the agent needs to know\"}" &
    "},\"required\":[\"name\",\"question\"]}"

  ConveneAgentsToolName* = "convene_agents"
  ConveneAgentsToolDescription* =
    "Put a question to several of the user's named agents and let them " &
    "deliberate: each answers on its own, then, in each further round, reads " &
    "the others' answers and revises. Returns the transcript; you are the " &
    "lead and write the synthesis for the user. 2-5 agents, 1-3 rounds."
  ConveneAgentsToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"agents\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}," &
    "\"question\":{\"type\":\"string\"}," &
    "\"context\":{\"type\":\"string\"}," &
    "\"rounds\":{\"type\":\"integer\",\"description\":\"1-3, default 2\"}" &
    "},\"required\":[\"agents\",\"question\"]}"

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

# ── session_search ────────────────────────────────────────────────────────────
const
  SessionSearchToolName* = "session_search"
  SessionSearchToolDescription* =
    "Search the user's whole conversation history (every past session and " &
    "what was compacted out of this one), plus MEMORY.md. Three ways in: " &
    "`phrase` finds every message holding an exact string, with neighbouring " &
    "messages, newest first and paginated (use `count` first to see how many); " &
    "best for strings you have already seen: names, numbers, dates, IDs, " &
    "error text. `query` ranks conversations by its terms when you have no " &
    "exact string. `session_id` with `around` reads the messages around a hit. " &
    "Narrow with `since`/`until` (7d, 24h, 2w or YYYY-MM-DD). Case and accents " &
    "are ignored. If the first words find nothing useful, try others: " &
    "synonyms, a shorter word, the singular. Finding nothing only means these " &
    "words are not there; it may have been said in other words, so if it is " &
    "still not found, say you don't remember it, not that it was never said. " &
    "Results are this user's only and read-only."
  SessionSearchToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"phrase\":{\"type\":\"string\",\"description\":\"Exact string to find in every message\"}," &
    "\"query\":{\"type\":\"string\",\"description\":\"Terms to rank conversations by\"}," &
    "\"session_id\":{\"type\":\"string\",\"description\":\"Read this session\"}," &
    "\"around\":{\"type\":\"integer\",\"description\":\"With session_id: the message # to read around (default: the last)\"}," &
    "\"since\":{\"type\":\"string\",\"description\":\"7d, 24h, 2w or YYYY-MM-DD\"}," &
    "\"until\":{\"type\":\"string\",\"description\":\"7d, 24h, 2w or YYYY-MM-DD\"}," &
    "\"limit\":{\"type\":\"integer\",\"description\":\"phrase: matches per page (10, max 30); query: conversations (8, max 20)\"}," &
    "\"offset\":{\"type\":\"integer\",\"description\":\"phrase: continue from this match\"}," &
    "\"context\":{\"type\":\"integer\",\"description\":\"phrase: neighbouring messages per side (0-3); session_id: radius (default 5, max 20)\"}," &
    "\"count\":{\"type\":\"boolean\",\"description\":\"phrase: only count matches per session\"}," &
    "\"order\":{\"type\":\"string\",\"enum\":[\"newest\",\"oldest\"]}," &
    "\"include_memory\":{\"type\":\"boolean\",\"description\":\"query: also search MEMORY.md (default true)\"}" &
    "}}"

# ── memory_ingest ─────────────────────────────────────────────────────────────
const
  MemoryIngestToolName* = "memory_ingest"
  MemoryIngestToolDescription* =
    "Read a text file from the current workspace or a text blob and append it " &
    "to the user's long-term memory in bounded chunks. Use this when the user " &
    "asks to ingest a document, import notes, or save a substantial memory. " &
    "The path must be inside the workspace; binary and oversized files are rejected."
  MemoryIngestToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"path\":{\"type\":\"string\",\"description\":\"Workspace-relative text file to ingest\"}," &
    "\"text\":{\"type\":\"string\",\"description\":\"Inline text to ingest when no path is given\"}," &
    "\"chunk_chars\":{\"type\":\"integer\",\"description\":\"Chunk size in characters (default: 2000, range: 500..8000)\"}," &
    "\"max_chunks\":{\"type\":\"integer\",\"description\":\"Maximum chunks to ingest (default: 100, range: 1..500)\"}" &
    "}}"

# ── spawn_subagent ────────────────────────────────────────────────────────────
const
  SpawnSubagentToolName* = "spawn_subagent"
  SpawnSubagentToolDescription* =
    "Delegate a focused task to an isolated subagent. The child receives only " &
    "the explicit task/context, a separate paddock, read-only tools by default " &
    "and the inherited approval policy. It cannot spawn another subagent. " &
    "With wait=true (default) returns the structured result; with wait=false " &
    "returns a subagent_id for await_subagent."
  SpawnSubagentToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"task\":{\"type\":\"string\",\"description\":\"Task for the child to complete\"}," &
    "\"context\":{\"type\":\"string\",\"description\":\"Explicit context to pass; parent history is not inherited\"}," &
    "\"tools\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}," &
    "\"description\":\"Optional subset of allowed read-only tools\"}," &
    "\"max_tool_calls\":{\"type\":\"integer\",\"description\":\"Tool-call budget (default: 24, max: 100)\"}," &
    "\"max_tokens\":{\"type\":\"integer\",\"description\":\"Token budget (default: 32000, max: 128000)\"}," &
    "\"max_duration_sec\":{\"type\":\"integer\",\"description\":\"Wall-clock budget in seconds (default: 120, max: 600)\"}," &
    "\"wait\":{\"type\":\"boolean\",\"description\":\"Wait for the result (default: true)\"}" &
    "},\"required\":[\"task\"]}"

# ── await_subagent ────────────────────────────────────────────────────────────
const
  AwaitSubagentToolName* = "await_subagent"
  AwaitSubagentToolDescription* =
    "Wait for a background subagent created with wait=false and return its " &
    "structured result, including status, text, error, tool_calls, duration_ms " &
    "and token usage."
  AwaitSubagentToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"subagent_id\":{\"type\":\"string\",\"description\":\"Subagent ID\"}}" &
    ",\"required\":[\"subagent_id\"]}"

# ── list_subagents ────────────────────────────────────────────────────────────
const
  ListSubagentsToolName* = "list_subagents"
  ListSubagentsToolDescription* =
    "List subagents in this session with status, age, last activity and budget usage."
  ListSubagentsToolSchema* =
    "{\"type\":\"object\",\"properties\":{}}"

# ── cancel_subagent ───────────────────────────────────────────────────────────
const
  CancelSubagentToolName* = "cancel_subagent"
  CancelSubagentToolDescription* =
    "Cancel a running subagent by ID. Idempotent: completed or already " &
    "cancelled subagents return cancelled=true without side effects."
  CancelSubagentToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"subagent_id\":{\"type\":\"string\",\"description\":\"Subagent ID to cancel\"}}" &
    ",\"required\":[\"subagent_id\"]}"
