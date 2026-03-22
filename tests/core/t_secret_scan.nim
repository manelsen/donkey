## Secret scan unit tests.

import std/[strutils, unittest]
import donkey/core/security/secret_scan

suite "secret_scan — known prefixes":

  test "detects OpenAI-style sk- key":
    let findings = scanForSecrets("here is your key: sk-abcdefghijklmnopqrstuvwxyz1234")
    check findings.len > 0
    check findings[0].kind == skKnownPrefix

  test "detects Anthropic sk-ant- key":
    let findings = scanForSecrets("token=sk-ant-api03-abcdefghijklmnopqrst")
    check findings.len > 0

  test "detects AWS AKIA access key":
    let findings = scanForSecrets("aws key: AKIAIOSFODNN7EXAMPLE")
    check findings.len > 0

  test "detects GitHub ghp_ token":
    let findings = scanForSecrets("export GH_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz123456")
    check findings.len > 0

  test "detects Slack xoxb- token":
    let findings = scanForSecrets("SLACK_BOT_TOKEN=xoxb-12345-67890-abcdefghijklmnopq")
    check findings.len > 0

  test "no findings for short sk- word":
    ## sk-abc is too short to be a real key
    let findings = scanForSecrets("sk-abc is not a key")
    check findings.len == 0

  test "no findings for ordinary text":
    let findings = scanForSecrets("the quick brown fox jumps over the lazy dog")
    check findings.len == 0

  test "hint redacts most of the key":
    let findings = scanForSecrets("key: sk-abcdefghijklmnopqrstuvwxyz")
    check findings.len > 0
    check findings[0].hint.endsWith("...")
    check findings[0].hint.len < 20   ## must not expose the whole key

suite "secret_scan — bearer tokens":

  test "detects Bearer <long-token>":
    let findings = scanForSecrets("Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9abcdefghij")
    check findings.len > 0
    check findings[0].kind == skBearerToken

  test "Bearer with short value not flagged":
    let findings = scanForSecrets("Authorization: Bearer shortval")
    check findings.len == 0

suite "secret_scan — contextual key=value":

  test "detects api_key=<long-value>":
    let findings = scanForSecrets("api_key=abcdefghijklmnopqrstuvwxyz123456")
    check findings.len > 0
    check findings[0].kind == skContextualKey

  test "detects password=<long-value>":
    let findings = scanForSecrets("password=SuperSecretP@ssw0rd12345678!")
    check findings.len > 0

  test "detects token: <long-value> (colon form)":
    let findings = scanForSecrets("token: abcdefghijklmnopqrstuvwxyz123456")
    check findings.len > 0

  test "short contextual value not flagged":
    let findings = scanForSecrets("token=short")
    check findings.len == 0

  test "filename with key in name not flagged":
    let findings = scanForSecrets("api_key_test.nim is a file")
    check findings.len == 0

suite "secret_scan — hasSecrets helper":

  test "hasSecrets returns true when secrets found":
    check hasSecrets("sk-abcdefghijklmnopqrstuvwxyz")

  test "hasSecrets returns false for clean text":
    check not hasSecrets("no secrets here at all")
