## learned_skill_pure — skills the agent learns, the pure half (E7.1).
##
## A skill is procedural memory: a SKILL.md with a frontmatter naming it and
## saying when it applies, then the instructions (the agentskills.io format
## Hermes and other agents use). The agent writes them from conversations,
## so they are scanned before they are kept: a skill is a standing
## instruction, and an injection written into one would persist. The guard
## blocks what reads like exfiltration, prompt injection, hidden characters
## or destructive commands. Categories and patterns derived from
## hermes-agent (MIT), tools/skills_guard.py; plain text checks, no regex
## engine, so the domain stays free of PCRE.

import std/[strutils, unicode]
import ../../core/pipeops

const
  MaxSkillNameLen* = 64
  MaxSkillDescriptionLen* = 1024
  MaxSkillBytes* = 32_000

type
  SkillDoc* = object
    name*, description*, body*: string

  GuardFinding* = object
    id*, category*, reason*: string

func validSkillName*(name: string): bool =
  name.len in 1 .. MaxSkillNameLen and name[0] != '-' and
    name.allCharsInSet({'a'..'z', '0'..'9', '-'})

func unquoted(v: string): string =
  let t = v.strip
  if t.len >= 2 and ((t[0] == '"' and t[^1] == '"') or (t[0] == '\'' and t[^1] == '\'')):
    t[1 ..< t.len - 1]
  else: t

func parseSkillMd*(text: string): Result[SkillDoc, string] =
  if text.len > MaxSkillBytes:
    return err("the skill is larger than " & $MaxSkillBytes & " bytes")
  let t = text.replace("\r\n", "\n")
  if not t.startsWith("---\n"):
    return err("a SKILL.md starts with a '---' frontmatter")
  let close = t.find("\n---", 4)
  if close < 0:
    return err("the frontmatter is not closed with '---'")
  var doc = SkillDoc()
  for line in t[4 ..< close].splitLines:
    let colon = line.find(':')
    if colon <= 0: continue
    let key = line[0 ..< colon].strip
    let value = unquoted(line[colon + 1 .. ^1])
    case key
    of "name": doc.name = value
    of "description": doc.description = value
    else: discard
  var rest = t[close + 4 .. ^1]
  if rest.startsWith("\n"): rest = rest[1 .. ^1]
  doc.body = rest.strip()
  if not validSkillName(doc.name):
    return err("the name must be 1-64 of a-z, 0-9 and '-': " & doc.name)
  if doc.description.strip.len == 0:
    return err("the description (when to use the skill) is required")
  if doc.description.len > MaxSkillDescriptionLen:
    return err("the description is longer than " & $MaxSkillDescriptionLen & " characters")
  if doc.body.strip.len == 0:
    return err("the skill has no instructions")
  ok(doc)

func yamlValue(v: string): string =
  if v.contains({':', '#', '\'', '"'}) or v.startsWith(" ") or v.endsWith(" "):
    "\"" & v.replace("\\", "\\\\").replace("\"", "\\\"") & "\""
  else: v

func renderSkillMd*(s: SkillDoc): string =
  "---\nname: " & s.name & "\ndescription: " & yamlValue(s.description.replace("\n", " ")) &
    "\n---\n\n" & s.body.strip & "\n"

# ── The guard ─────────────────────────────────────────────────────────────────

func normalized(text: string): string =
  ## Lowercase, every run of whitespace as one space.
  var lastSpace = false
  for c in text.toLowerAscii:
    if c in Whitespace:
      if not lastSpace: result.add ' '
      lastSpace = true
    else:
      result.add c
      lastSpace = false

func near(text, a, b: string; window = 60): bool =
  ## `a`, then `b` within `window` characters.
  var i = text.find(a)
  while i >= 0:
    let j = text.find(b, i + a.len)
    if j >= 0 and j - (i + a.len) <= window: return true
    i = text.find(a, i + 1)
  false

func anyOf(text: string; words: openArray[string]): bool =
  for w in words:
    if w in text: return true
  false

const
  SecretWords = ["key", "token", "secret", "password", "passwd", "credential"]
  NetWords = ["curl ", "wget ", "fetch(", "http://", "https://", "requests.", "httpx.", "nc "]
  SecretPaths = ["~/.ssh", ".ssh/id_", "~/.aws", ".aws/credentials", ".gnupg", "~/.kube",
                 ".kube/config", ".docker/config.json", "donkey.env", "secrets.enc",
                 "/etc/shadow", ".netrc", ".git-credentials"]
  InvisibleRanges = [(0x200B, 0x200F), (0x202A, 0x202E), (0x2060, 0x2064), (0xFEFF, 0xFEFF)]

func hasSecretVar(line: string): bool =
  ## `$NAME`, `${NAME}` or `$(...)` where the name looks like a secret.
  var i = line.find('$')
  while i >= 0:
    let tail = line[i + 1 ..< min(line.len, i + 48)]
    if tail.startsWith("(") or anyOf(tail, SecretWords): return true
    i = line.find('$', i + 1)
  false

func scanText(t: string; findings: var seq[GuardFinding]) =
  template found(fid, fcategory, freason: string) =
    findings.add GuardFinding(id: fid, category: fcategory, reason: freason)
  for line in t.splitLines:
    if hasSecretVar(line) and anyOf(line, NetWords):
      found("env_exfil", "exfiltration", "a network call carrying a secret variable")
    if ("](" in line) and hasSecretVar(line):
      found("md_exfil", "exfiltration", "a markdown link or image carrying a variable")
  for p in SecretPaths:
    if p in t:
      found("secret_path", "exfiltration", "refers to a credentials file: " & p)
      break
  if anyOf(t, ["printenv", "os.environ", "process.env", "env | ", "set | curl"]):
    found("env_dump", "exfiltration", "dumps the environment")
  if near(t, "ignore", "instructions") or near(t, "ignore", "previous") or
      near(t, "disregard", "rules") or near(t, "disregard", "instructions") or
      near(t, "forget", "instructions") or near(t, "forget", "your rules"):
    found("ignore_instructions", "injection", "prompt injection: ignore or forget the instructions")
  if anyOf(t, ["you are now ", "from now on you are", "pretend to be ", "act as an ai without",
               "without any restrictions", "without restrictions", "jailbreak", "developer mode"]):
    found("role_hijack", "injection", "prompt injection: takes over the agent's role")
  if anyOf(t, ["do not tell the user", "don't tell the user", "dont tell the user",
               "hide this from the user", "without telling the user", "do not mention this to"]):
    found("deception", "injection", "prompt injection: hides something from the user")
  if near(t, "system prompt", "verbatim") or near(t, "reveal", "system prompt") or
      near(t, "print", "system prompt") or near(t, "new system prompt", "") or
      near(t, "override", "system prompt"):
    found("system_prompt", "injection", "prompt injection: reads or replaces the system prompt")
  if anyOf(t, ["not watching", "no one is watching", "when unobserved", "nobody is watching"]):
    found("conditional", "injection", "prompt injection: behaves differently when unobserved")
  if anyOf(t, ["rm -rf /", "rm -rf ~", "rm -rf $home", "mkfs", "dd if=", ":(){", "> /dev/sd",
               "chmod -r 777 /", "chmod 777 /"]):
    found("destructive", "destructive", "a destructive command")

func scanSkill*(s: SkillDoc): seq[GuardFinding] =
  ## Empty when the skill may be kept.
  for r in (s.description & "\n" & s.body).runes:
    for (lo, hi) in InvisibleRanges:
      if int(r) >= lo and int(r) <= hi:
        result.add GuardFinding(id: "invisible", category: "obfuscation",
                                reason: "hidden or direction-changing characters")
        return
  scanText(normalized(s.description), result)
  scanText(normalized(s.body), result)

func guardReport*(findings: seq[GuardFinding]): string =
  var reasons: seq[string]
  for f in findings:
    if f.reason notin reasons: reasons.add f.reason
  "blocked: " & reasons.join("; ")
