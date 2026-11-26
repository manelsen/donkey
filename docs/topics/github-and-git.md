# GitHub and git tools

Two read-only tools for working with code. Both run their I/O on the blocking
executor, never on the event loop.

## `github`

Offered when `GITHUB_TOKEN` is set (a fine-grained token with read access to
the repositories it should see is enough).

| Action | What it reads |
|---|---|
| `list_issues` | A repository's issues (pull requests left out), by state |
| `get_issue` | One issue, its labels and body (cut at 4000 characters) |
| `list_prs` | A repository's pull requests, by state |
| `get_pr` | One pull request: branches, merge state, body |
| `list_commits` | The last commits, optionally of one branch |
| `search_code` | Code search, optionally in one repository |

It only talks to `api.github.com`, and every answer starts with a note that
the content is written by third parties. Issues and pull requests are the
prompt-injection vector described in `CLAUDE.md`, so the tool cannot write:
opening issues or commenting is left for a decision about approvals.

## `git_inspect`

Always offered. `path` is a repository's folder in the person's workspace (the
same confinement as the `fs_*` tools).

| Action | Command |
|---|---|
| `status` | `git status --short --branch` |
| `log` | `git log --oneline -n<count>` (1–50, default 10) |
| `diff` | `git diff --stat`, or the diff of one `file` |
| `branches` | `git branch --all` |
| `show` | `git show --stat <rev>` (default `HEAD`) |

A repository's own configuration can make git run programs (`core.fsmonitor`
on `status`, an external diff, a textconv filter, hooks, a pager), so every
command turns those off on the command line and a revision or a file can never
become an option. Output is cut at 12000 characters; a command gets 20 s.
