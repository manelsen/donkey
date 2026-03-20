## clawhub_registry — remote ClawHub client + local install state.
##
## Covers search, metadata lookup, zip download, deterministic bundle hashing,
## local lock/origin files, and install/update validation.

import std/[algorithm, httpclient, json, os, osproc, strutils, tables, times, uri]
import wrappers/openssl
import ../core/pipeops

const
  ClawhubDefaultRegistry* = "https://clawhub.ai"
  ClawhubApiSearch*       = "/api/v1/search"
  ClawhubApiSkills*       = "/api/v1/skills"
  ClawhubApiDownload*     = "/api/v1/download"
  ClawhubDotDir*          = ".clawhub"

type
  RemoteSkillSearchHit* = object
    slug*:        string
    displayName*: string
    summary*:     string
    version*:     string
    score*:       float

  RemoteSkillVersionFile* = object
    path*:   string
    sha256*: string
    size*:   int

  RemoteSkillVersion* = object
    version*: string
    files*:   seq[RemoteSkillVersionFile]

  RemoteSkillOrigin* = object
    version*:          int
    registry*:         string
    slug*:             string
    installedVersion*: string
    installedAt*:      int64

  RemoteSkillLockEntry* = object
    version*:     string
    installedAt*: int64

  RemoteSkillLockfile* = object
    version*: int
    skills*:  Table[string, RemoteSkillLockEntry]

  InstalledRemoteSkill* = object
    slug*:    string
    version*: string
    skillMd*: string

func normalizeRegistryUrl*(registry: string): string =
  let base = if registry.strip().len > 0: registry.strip() else: ClawhubDefaultRegistry
  if base.endsWith("/"): base[0 .. ^2] else: base

func registryUrl*(registry, path: string): string =
  normalizeRegistryUrl(registry) & path

func remoteSkillsDir*(home: string): string =
  home / "clawhub" / "skills"

func remoteSkillDir*(home, slug: string): string =
  remoteSkillsDir(home) / slug

func remoteSkillLockPath*(home: string): string =
  home / "clawhub" / "lock.json"

func remoteSkillOriginPath*(skillDir: string): string =
  skillDir / ClawhubDotDir / "origin.json"

proc remoteSkillReadmePath*(skillDir: string): string =
  for candidate in @["SKILL.md", "skill.md"]:
    let path = skillDir / candidate
    if fileExists(path):
      return path
  ""

func bytesToString(bytes: seq[byte]): string =
  result = newString(bytes.len)
  for i, b in bytes:
    result[i] = char(b)

func stringToBytes(text: string): seq[byte] =
  result = newSeq[byte](text.len)
  for i, ch in text:
    result[i] = byte(ord(ch))

proc sha256Hex*(bytes: openArray[byte]): string =
  let ctx = EVP_MD_CTX_create()
  defer: EVP_MD_CTX_destroy(ctx)
  discard EVP_DigestInit_ex(ctx, EVP_sha256())
  if bytes.len > 0:
    discard EVP_DigestUpdate(ctx, unsafeAddr bytes[0], bytes.len.cuint)
  var digest: array[32, byte]
  var digestLen: cuint = 0
  discard EVP_DigestFinal_ex(ctx, addr digest[0], addr digestLen)
  for i in 0 ..< digestLen.int:
    result.add(toHex(digest[i].int, 2).toLowerAscii)

proc sha256Hex*(text: string): string =
  sha256Hex(text.stringToBytes)

proc sha256FileHex*(path: string): string =
  sha256Hex(readFile(path))

proc buildSkillFingerprint*(files: seq[RemoteSkillVersionFile]): string =
  var normalized: seq[RemoteSkillVersionFile] = @[]
  for file in files:
    if file.path.len > 0 and file.sha256.len > 0:
      normalized.add(file)
  normalized.sort(proc(a, b: RemoteSkillVersionFile): int = cmp(a.path, b.path))
  var payload: seq[string] = @[]
  for file in normalized:
    payload.add(file.path & ":" & file.sha256)
  sha256Hex(payload.join("\n"))

proc parseSearchHits*(j: JsonNode): seq[RemoteSkillSearchHit] =
  let results = j.getOrDefault("results")
  if results == nil or results.kind != JArray:
    return @[]
  for item in results:
    result.add RemoteSkillSearchHit(
      slug: item.getOrDefault("slug").getStr(""),
      displayName: item.getOrDefault("displayName").getStr(""),
      summary: item.getOrDefault("summary").getStr(""),
      version: item.getOrDefault("version").getStr(""),
      score: item.getOrDefault("score").getFloat(0.0),
    )

proc parseLatestVersion*(j: JsonNode): string =
  j.getOrDefault("latestVersion").getOrDefault("version").getStr("")

proc parseRemoteSkillVersion*(j: JsonNode): RemoteSkillVersion =
  let version = j.getOrDefault("version")
  result.version = version.getOrDefault("version").getStr("")
  let files = version.getOrDefault("files")
  if files == nil or files.kind != JArray:
    return
  for file in files:
    result.files.add RemoteSkillVersionFile(
      path: file.getOrDefault("path").getStr(""),
      sha256: file.getOrDefault("sha256").getStr(""),
      size: file.getOrDefault("size").getInt(0),
    )

proc newRegistryClient*(registry: string): HttpClient =
  result = newHttpClient()
  result.headers = newHttpHeaders({
    "Accept": "application/json",
  })
  discard normalizeRegistryUrl(registry)

proc fetchJson*(registry, path: string): Result[JsonNode, string] =
  try:
    let client = newRegistryClient(registry)
    defer: client.close()
    let resp = client.get(registryUrl(registry, path))
    if resp.status[0] != '2':
      return err("ClawHub API error " & resp.status & ": " & resp.body)
    ok(parseJson(resp.body))
  except CatchableError as e:
    err(e.msg)

proc downloadZipBytes*(registry, slug, version: string): Result[seq[byte], string] =
  try:
    let client = newHttpClient()
    defer: client.close()
    var url = registryUrl(registry, ClawhubApiDownload)
    url.add(if '?' in url: "&" else: "?")
    url.add("slug=" & encodeUrl(slug))
    if version.len > 0:
      url.add("&version=" & encodeUrl(version))
    let resp = client.get(url)
    if resp.status[0] != '2':
      return err("ClawHub download error " & resp.status & ": " & resp.body)
    ok(resp.body.stringToBytes)
  except CatchableError as e:
    err(e.msg)

proc searchRemoteSkills*(registry, query: string; limit = 10): Result[seq[RemoteSkillSearchHit], string] =
  let path = ClawhubApiSearch & "?q=" & encodeUrl(query) & "&limit=" & $limit
  fetchJson(registry, path).map(parseSearchHits)

proc fetchRemoteSkillLatestVersion*(registry, slug: string): Result[string, string] =
  fetchJson(registry, ClawhubApiSkills & "/" & encodeUrl(slug)).map(parseLatestVersion)

proc fetchRemoteSkillVersion*(registry, slug, version: string): Result[RemoteSkillVersion, string] =
  let path = ClawhubApiSkills & "/" & encodeUrl(slug) & "/versions/" & encodeUrl(version)
  fetchJson(registry, path).map(parseRemoteSkillVersion)

proc writeRemoteSkillOrigin*(skillDir: string; origin: RemoteSkillOrigin) =
  let path = remoteSkillOriginPath(skillDir)
  createDir(parentDir(path))
  writeFile(path, $(%* {
    "version": origin.version,
    "registry": origin.registry,
    "slug": origin.slug,
    "installedVersion": origin.installedVersion,
    "installedAt": origin.installedAt,
  }) & "\n")

proc readRemoteSkillOrigin*(skillDir: string): Result[RemoteSkillOrigin, string] =
  let path = remoteSkillOriginPath(skillDir)
  if not fileExists(path):
    return err("Origin not found")
  try:
    let j = parseJson(readFile(path))
    ok(RemoteSkillOrigin(
      version: j.getOrDefault("version").getInt(1),
      registry: j.getOrDefault("registry").getStr(""),
      slug: j.getOrDefault("slug").getStr(""),
      installedVersion: j.getOrDefault("installedVersion").getStr(""),
      installedAt: j.getOrDefault("installedAt").getBiggestInt().int64,
    ))
  except CatchableError as e:
    err(e.msg)

proc defaultRemoteSkillLockfile*(): RemoteSkillLockfile =
  RemoteSkillLockfile(version: 1, skills: initTable[string, RemoteSkillLockEntry]())

proc readRemoteSkillLockfile*(home: string): RemoteSkillLockfile =
  let path = remoteSkillLockPath(home)
  if not fileExists(path):
    return defaultRemoteSkillLockfile()
  try:
    let j = parseJson(readFile(path))
    result = defaultRemoteSkillLockfile()
    result.version = j.getOrDefault("version").getInt(1)
    let skills = j.getOrDefault("skills")
    if skills != nil and skills.kind == JObject:
      for slug, node in skills:
        result.skills[slug] = RemoteSkillLockEntry(
          version: node.getOrDefault("version").getStr(""),
          installedAt: node.getOrDefault("installedAt").getBiggestInt().int64,
        )
  except:
    result = defaultRemoteSkillLockfile()

proc writeRemoteSkillLockfile*(home: string; lock: RemoteSkillLockfile) =
  let path = remoteSkillLockPath(home)
  createDir(parentDir(path))
  var skills = newJObject()
  for slug, entry in lock.skills.pairs:
    skills[slug] = %* {
      "version": entry.version,
      "installedAt": entry.installedAt,
    }
  writeFile(path, $(%* {
    "version": lock.version,
    "skills": skills,
  }) & "\n")

proc stripFrontmatter*(text: string): string =
  let lines = text.splitLines()
  if lines.len == 0 or lines[0].strip() != "---":
    return text.strip()
  for i in 1 ..< lines.len:
    if lines[i].strip() == "---":
      return lines[(i + 1) .. ^1].join("\n").strip()
  text.strip()

proc loadInstalledRemoteSkill*(home, slug: string): Result[InstalledRemoteSkill, string] =
  let skillDir = remoteSkillDir(home, slug)
  let origin = readRemoteSkillOrigin(skillDir).valueOr:
    return err(error)
  let readmePath = remoteSkillReadmePath(skillDir)
  if readmePath.len == 0:
    return err("Installed remote skill missing SKILL.md: " & slug)
  ok(InstalledRemoteSkill(
    slug: slug,
    version: origin.installedVersion,
    skillMd: stripFrontmatter(readFile(readmePath)),
  ))

proc loadInstalledRemoteSkills*(home: string): seq[InstalledRemoteSkill] =
  let lock = readRemoteSkillLockfile(home)
  var slugs: seq[string] = @[]
  for slug, _ in lock.skills.pairs:
    slugs.add(slug)
  slugs.sort(system.cmp[string])
  for slug in slugs:
    let loaded = loadInstalledRemoteSkill(home, slug)
    if loaded.isOk:
      result.add(loaded.get())

proc buildInstalledRemoteSkillPrompt*(skills: seq[InstalledRemoteSkill]): string =
  if skills.len == 0:
    return ""
  result = "## Installed remote skills\n"
  for skill in skills:
    result.add("\n### " & skill.slug)
    if skill.version.len > 0:
      result.add(" v" & skill.version)
    result.add("\n")
    result.add(skill.skillMd)
    result.add("\n")

proc walkSkillFiles*(skillDir: string): seq[string] =
  if not dirExists(skillDir):
    return @[]
  for path in walkDirRec(skillDir):
    let rel = relativePath(path, skillDir).replace('\\', '/')
    if rel.len == 0 or rel.startsWith(ClawhubDotDir & "/") or rel.startsWith(".git/") or rel.startsWith("node_modules/"):
      continue
    result.add(rel)

proc buildLocalSkillFiles*(skillDir: string): seq[RemoteSkillVersionFile] =
  for rel in walkSkillFiles(skillDir):
    let full = skillDir / rel
    if not fileExists(full):
      continue
    result.add RemoteSkillVersionFile(
      path: rel,
      sha256: sha256FileHex(full),
      size: getFileSize(full).int,
    )

proc validateInstalledSkillDir*(skillDir: string; remoteFiles: seq[RemoteSkillVersionFile]): Result[void, string] =
  let localFiles = buildLocalSkillFiles(skillDir)
  let localFingerprint = buildSkillFingerprint(localFiles)
  let remoteFingerprint = buildSkillFingerprint(remoteFiles)
  if localFingerprint != remoteFingerprint:
    return err("Installed bundle fingerprint mismatch")
  ok()

proc extractZipToDir*(zipBytes: seq[byte]; targetDir: string): Result[void, string] =
  let tmpZip = targetDir.parentDir / (targetDir.extractFilename & ".tmp.zip")
  try:
    createDir(targetDir.parentDir)
    writeFile(tmpZip, bytesToString(zipBytes))
    let unzipCmd = quoteShellCommand(@["unzip", "-oq", tmpZip, "-d", targetDir])
    let (outp, code) = execCmdEx(unzipCmd)
    if code != 0:
      let tarCmd = quoteShellCommand(@["bsdtar", "-xf", tmpZip, "-C", targetDir])
      let (tarOut, tarCode) = execCmdEx(tarCmd)
      if tarCode != 0:
        return err((outp & "\n" & tarOut).strip())
    ok()
  except CatchableError as e:
    err(e.msg)
  finally:
    if fileExists(tmpZip):
      removeFile(tmpZip)

proc installRemoteSkill*(home, registry, slug: string; force = false): Result[RemoteSkillOrigin, string] =
  let latestVersion = fetchRemoteSkillLatestVersion(registry, slug).valueOr:
    return err(error)
  if latestVersion.len == 0:
    return err("Could not resolve latest version for " & slug)
  let remoteVersion = fetchRemoteSkillVersion(registry, slug, latestVersion).valueOr:
    return err(error)
  let zipBytes = downloadZipBytes(registry, slug, latestVersion).valueOr:
    return err(error)
  let targetDir = remoteSkillDir(home, slug)
  if dirExists(targetDir):
    if not force:
      return err("Already installed: " & targetDir)
    removeDir(targetDir)
  createDir(targetDir)
  let extractResult = extractZipToDir(zipBytes, targetDir)
  if extractResult.isErr:
    if dirExists(targetDir): removeDir(targetDir)
    return err(extractResult.error)
  let validateResult = validateInstalledSkillDir(targetDir, remoteVersion.files)
  if validateResult.isErr:
    if dirExists(targetDir): removeDir(targetDir)
    return err(validateResult.error)
  let origin = RemoteSkillOrigin(
    version: 1,
    registry: normalizeRegistryUrl(registry),
    slug: slug,
    installedVersion: latestVersion,
    installedAt: getTime().toUnix(),
  )
  writeRemoteSkillOrigin(targetDir, origin)
  var lock = readRemoteSkillLockfile(home)
  lock.skills[slug] = RemoteSkillLockEntry(version: latestVersion, installedAt: origin.installedAt)
  writeRemoteSkillLockfile(home, lock)
  ok(origin)

proc updateRemoteSkill*(home, registry: string; slug: string; force = false): Result[string, string] =
  let targetDir = remoteSkillDir(home, slug)
  let origin = readRemoteSkillOrigin(targetDir).valueOr:
    return err(error)
  let currentVersion = origin.installedVersion
  let latestVersion = fetchRemoteSkillLatestVersion(registry, slug).valueOr:
    return err(error)
  if latestVersion.len == 0:
    return err("Could not resolve latest version for " & slug)
  if latestVersion == currentVersion:
    return ok(currentVersion)
  let currentRemoteVersion = fetchRemoteSkillVersion(origin.registry, slug, currentVersion).valueOr:
    return err(error)
  if not force:
    let validateResult = validateInstalledSkillDir(targetDir, currentRemoteVersion.files)
    if validateResult.isErr:
      return err("Local changes detected for " & slug & " (use --force to overwrite)")
  installRemoteSkill(home, registry, slug, force = true).map(proc(origin: RemoteSkillOrigin): string = origin.installedVersion)
