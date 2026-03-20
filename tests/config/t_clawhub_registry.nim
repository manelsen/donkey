import std/[json, os, strutils, tables, unittest]
import donkey/config/clawhub_registry
import donkey/core/pipeops

suite "clawhub_registry":

  test "parseSearchHits reads remote results":
    let hits = parseSearchHits(%* {
      "results": [
        {
          "slug": "gifgrep",
          "displayName": "GifGrep",
          "summary": "Search gifs",
          "version": "1.2.3",
          "score": 0.91
        }
      ]
    })
    check hits.len == 1
    check hits[0].slug == "gifgrep"
    check hits[0].displayName == "GifGrep"
    check hits[0].version == "1.2.3"
    check hits[0].summary == "Search gifs"

  test "parseRemoteSkillVersion reads files and version":
    let version = parseRemoteSkillVersion(%* {
      "version": {
        "version": "1.2.3",
        "files": [
          {"path": "SKILL.md", "sha256": "abc", "size": 10},
          {"path": "docs/readme.md", "sha256": "def", "size": 20}
        ]
      }
    })
    check version.version == "1.2.3"
    check version.files.len == 2
    check version.files[0].path == "SKILL.md"
    check version.files[1].sha256 == "def"

  test "buildSkillFingerprint is order-independent":
    let a = buildSkillFingerprint(@[
      RemoteSkillVersionFile(path: "b.txt", sha256: "bbb"),
      RemoteSkillVersionFile(path: "a.txt", sha256: "aaa"),
    ])
    let b = buildSkillFingerprint(@[
      RemoteSkillVersionFile(path: "a.txt", sha256: "aaa"),
      RemoteSkillVersionFile(path: "b.txt", sha256: "bbb"),
    ])
    check a == b

  test "lockfile round-trip preserves installed versions":
    let home = getTempDir() / "donkey_clawhub_lock_test"
    defer:
      if dirExists(home):
        removeDir(home)
    var lock = defaultRemoteSkillLockfile()
    lock.skills["gifgrep"] = RemoteSkillLockEntry(version: "1.2.3", installedAt: 100)
    writeRemoteSkillLockfile(home, lock)
    let loaded = readRemoteSkillLockfile(home)
    check loaded.skills.hasKey("gifgrep")
    check loaded.skills["gifgrep"].version == "1.2.3"

  test "origin round-trip preserves slug and version":
    let skillDir = getTempDir() / "donkey_clawhub_origin_test"
    defer:
      if dirExists(skillDir):
        removeDir(skillDir)
    let origin = RemoteSkillOrigin(
      version: 1,
      registry: "https://clawhub.ai",
      slug: "gifgrep",
      installedVersion: "1.2.3",
      installedAt: 123'i64,
    )
    writeRemoteSkillOrigin(skillDir, origin)
    let loadedRes = readRemoteSkillOrigin(skillDir)
    check not loadedRes.isErr
    let loaded = loadedRes.value
    check loaded.slug == "gifgrep"
    check loaded.installedVersion == "1.2.3"

  test "validateInstalledSkillDir accepts matching local bundle":
    let skillDir = getTempDir() / "donkey_clawhub_validate_ok"
    defer:
      if dirExists(skillDir):
        removeDir(skillDir)
    createDir(skillDir)
    writeFile(skillDir / "SKILL.md", "# Skill\n")
    writeFile(skillDir / "README.md", "docs\n")
    let files = buildLocalSkillFiles(skillDir)
    let validated = validateInstalledSkillDir(skillDir, files)
    check not validated.isErr

  test "validateInstalledSkillDir rejects mismatched bundle":
    let skillDir = getTempDir() / "donkey_clawhub_validate_err"
    defer:
      if dirExists(skillDir):
        removeDir(skillDir)
    createDir(skillDir)
    writeFile(skillDir / "SKILL.md", "# Skill\n")
    let validated = validateInstalledSkillDir(skillDir, @[
      RemoteSkillVersionFile(path: "SKILL.md", sha256: repeat("a", 64), size: 8)
    ])
    check validated.isErr

  test "stripFrontmatter removes yaml block from SKILL.md":
    let text = """---
name: demo
description: hello
---
Body line 1
Body line 2
"""
    check stripFrontmatter(text) == "Body line 1\nBody line 2"

  test "buildInstalledRemoteSkillPrompt renders installed skills":
    let prompt = buildInstalledRemoteSkillPrompt(@[
      InstalledRemoteSkill(slug: "demo-skill", version: "1.2.3", skillMd: "Use curl carefully."),
    ])
    check prompt.contains("demo-skill v1.2.3")
    check prompt.contains("Use curl carefully.")
