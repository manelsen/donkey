## git_inspect_pure — the git_inspect tool, the pure half (second round,
## front 2).
##
## Read-only git commands on a repository inside the paddock: status, log,
## diff, branches, show. A repository's own configuration can make git run
## programs (core.fsmonitor on status, an external diff, a textconv filter,
## hooks, a pager), so every command turns those off on the command line,
## and a revision or a file can never become an option.

import std/[json, strutils]
import ../../core/pipeops

const
  GitOutputChars* = 12_000
  GitActions = ["status", "log", "diff", "branches", "show"]

type
  GitInspectContext* = object
    action*, path*, file*, rev*: string
    count*: int

func validRev(rev: string): bool =
  rev.len > 0 and rev.len <= 100 and rev[0] != '-' and ".." notin rev and
    rev.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '_', '.', '/', '~', '^', '-', '@'})

func validFile(file: string): bool =
  file.len > 0 and file[0] notin {'-', '/'} and ".." notin file.split('/') and
    not file.contains({'\0', '\n', '\r', '\\'})

proc parseGitInspectContext*(j: JsonNode): Result[GitInspectContext, string] =
  let action = j{"action"}.getStr.strip.toLowerAscii
  if action notin GitActions:
    return err("Error: unknown action '" & action & "' (" & GitActions.join(", ") &
               "; the tool only reads)")
  let path = j{"path"}.getStr.strip
  if path.len == 0:
    return err("Error: 'path' (the repository, in the workspace) is required")
  var c = GitInspectContext(action: action, path: path, file: j{"file"}.getStr.strip,
                            rev: j{"rev"}.getStr.strip,
                            count: max(1, min(50, j{"count"}.getInt(10))))
  if c.file.len > 0 and not validFile(c.file):
    return err("Error: 'file' must be a path inside the repository")
  if action == "show":
    if c.rev.len == 0: c.rev = "HEAD"
    if not validRev(c.rev): return err("Error: not a revision: " & c.rev)
  elif c.rev.len > 0:
    return err("Error: 'rev' is only for show")
  ok(c)

func gitArgv*(c: GitInspectContext; repoDir: string): seq[string] =
  result = @["git", "-C", repoDir, "--no-pager",
             "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null",
             "-c", "diff.external=", "-c", "core.pager=cat",
             "-c", "protocol.allow=never", "-c", "core.quotepath=off"]
  case c.action
  of "status": result.add @["status", "--short", "--branch"]
  of "log": result.add @["log", "--oneline", "-n" & $c.count]
  of "branches": result.add @["branch", "--all", "--no-color"]
  of "diff":
    result.add @["diff", "--no-ext-diff", "--no-textconv"]
    if c.file.len > 0: result.add @["--", c.file]
    else: result.add "--stat"
  else:
    result.add @["show", "--no-ext-diff", "--no-textconv", "--stat", c.rev]

func capGitOutput*(output: string): string =
  if output.len <= GitOutputChars: output
  else: output[0 ..< GitOutputChars] & "\n… (cut at " & $GitOutputChars & " characters)"

const
  GitInspectToolName* = "git_inspect"
  GitInspectToolDescription* =
    "Look at a git repository in your workspace, read only: status, log (the " &
    "last commits), diff (summary, or one file), branches, show (a commit). " &
    "'path' is the repository's folder in the workspace."
  GitInspectToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"action\":{\"type\":\"string\",\"enum\":[\"status\",\"log\",\"diff\",\"branches\",\"show\"]}," &
    "\"path\":{\"type\":\"string\",\"description\":\"The repository's folder in the workspace\"}," &
    "\"count\":{\"type\":\"integer\",\"description\":\"log: how many commits, 1-50\"}," &
    "\"file\":{\"type\":\"string\",\"description\":\"diff: one file, relative to the repository\"}," &
    "\"rev\":{\"type\":\"string\",\"description\":\"show: the commit (default HEAD)\"}" &
    "},\"required\":[\"action\",\"path\"]}"
