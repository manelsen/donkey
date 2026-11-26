## The CLI's version line and help text. `donkey` prints them for
## --version and --help, and the help again when a command is unknown.

import ../core/app_meta

func versionText*(): string =
  AppSlug & " " & AppVersion

func cliHelpText*(): string =
  ## Every option and command the binary accepts.
  versionText() & """

Usage:
  """ & AppSlug & """ [options] [command]

Options:
  --version        Print version and exit
  --help           Show this help
  --config <path>  Path to """ & ConfigFileName & """  (default: ~/.config/""" & ConfigDirName & "/" & ConfigFileName & """)
  --dev-mode       Enable development mode (allows sandbox=none)

Commands:
  setup                          Interactive first-run configuration wizard
  about                          Show a concise runtime overview
  start                          Start the daemon
  ctl user list                  List registered users
  ctl user show <uuid>           Show user profile
  ctl user edit <uuid> <field> <value>
                                Edit a USER.md field
  ctl user revoke <uuid>        Revoke user access
  ctl user allow <uuid>         Restore user access
  ctl pair list                 List pending DM pairing requests
  ctl pair approve <code>       Approve a pairing request and allow the user
  ctl pair reject <code>        Discard a pairing request
  ctl approval list [user]      List pending tool approvals
  ctl approval approve <id>     Approve a pending tool call
  ctl approval deny <id>        Deny a pending tool call
  ctl secret set <name>         Encrypt a secret read from stdin
  ctl secret list               List stored secret names (never values)
  ctl secret remove <name>      Remove a stored secret
  ctl secret import-env [path]  Encrypt KEY=VALUE pairs from donkey.env
  ctl session list <uuid>        List active sessions for a user
  ctl tool install <command>            Register an MCP server (stdio)
  ctl tool add-http <url> [--token-env NAME | --oauth]
                                        Register an MCP server over HTTP
  ctl traces [--since 7d] [--user UUID]  per-turn traces (DONKEY_TRACES=on), as JSON lines
  ctl deliveries                         replies a channel refused: waiting for a retry, or dead
  ctl mcp login <url> [--client-id ID [--client-secret-env NAME]]
                                        OAuth login for an HTTP MCP server
  ctl skill search <query>              Search remote skills on ClawHub
  ctl skill install <name> <script>     Register a local Deno skill
  ctl skill install <slug>              Download/install remote skill bundle
  ctl skill list                        List local skill registry + remote installs
  ctl skill update <name> <script>      Update a local skill path
  ctl skill update [slug]               Update one/all remote installed skills
  ctl provider test <name>              Test provider connectivity
  ctl memory search <uuid> <q>   Semantic search in user memory via MAGMA
  ctl memory import <uuid>       Import .md paddock into MAGMA
  ctl memory export <uuid> [dir] Export MAGMA memory view as .md
  ctl status                     Show daemon status (daemon must be running)
  tui                            Open live TUI dashboard (daemon must be running)
  service install                Install as systemd --user service
  service remove                 Remove the systemd --user service
  service start                  systemctl --user start """ & AppSlug & """
  service stop                   systemctl --user stop """ & AppSlug & """
  service restart                systemctl --user restart """ & AppSlug & """
  service logs [-f] [--cat]      Show service logs (follow with -f, clean output with --cat)
  doctor                         Run the full runtime diagnostic
"""
