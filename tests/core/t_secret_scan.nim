## Secret scan unit tests.

import std/[sequtils, strutils, unittest]
import donkey/core/pipeops
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

suite "secret_scan — calculateEntropy":

  test "empty string has zero entropy":
    check calculateEntropy("") == 0.0'f64

  test "single repeated char has zero entropy":
    ## All probability mass on one symbol → 0 bits
    check calculateEntropy("aaaaaaaaaaaaaaaaaaa") == 0.0'f64

  test "two alternating chars have 1-bit entropy":
    let e = calculateEntropy("ababababababababab")
    check e > 0.99'f64 and e < 1.01'f64

  test "random-looking string has high entropy":
    ## A 32-char hex string drawn from 16 symbols → ~4 bits
    let e = calculateEntropy("a3f9b2c7d4e1a8f0b6c3d9e2a5f1b7c4")
    check e > 3.0'f64

  test "ordinary English word has low entropy":
    let e = calculateEntropy("passwordpasswordpassword")
    check e < 3.5'f64

  test "API key style token scores above threshold":
    ## Typical API keys mix upper/lower/digits → entropy > 4
    let e = calculateEntropy("sK3rT9pQwX2mNvL5hR8aB4cE7gF1dH6j")
    check e > 3.5'f64

suite "secret_scan — entropyAbove":

  test "entropyAbove(3.5) true for high-entropy token":
    check entropyAbove(3.5'f64, "sK3rT9pQwX2mNvL5hR8aB4cE7gF1dH6j")

  test "entropyAbove(3.5) false for repeated chars":
    check not entropyAbove(3.5'f64, "aaaaaaaaaaaaaaaaaaa")

suite "secret_scan — high-entropy detection":

  test "detects random-looking token not matching any prefix":
    ## A base64-like string with no known prefix but high entropy
    let findings = scanForSecrets("config: sK3rT9pQwX2mNvL5hR8aB4cE7gF1dH6j")
    check findings.len > 0
    check findings[^1].kind == skHighEntropy

  test "low-entropy long token not flagged as high-entropy":
    let findings = scanForSecrets("description: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    let highEntropyFindings = findings.filterIt(it.kind == skHighEntropy)
    check highEntropyFindings.len == 0

suite "secret_scan — pipeops operators":

  test "|> scanForSecrets — unary pipe works":
    ## |> pipes text through scanForSecrets as a unary transform
    let findings = "sk-abcdefghijklmnopqrstuvwxyz" |> scanForSecrets
    check findings.len > 0

  test "|> calculateEntropy — pure transform chain":
    ## Chain two pure unary functions
    let entropy = "sK3rT9pQwX2mNvL5hR8aB4cE7" |> calculateEntropy
    check entropy > 3.0'f64

  test "|>-> entropyAbove — last-arg pipe":
    ## entropyAbove takes (threshold, s) — s is piped as last arg
    let isHigh = "sK3rT9pQwX2mNvL5hR8aB4cE7gF1dH6j" |>-> entropyAbove(3.5'f64)
    check isHigh

  test "|>-> entropyAbove(0.0) always true for non-empty string":
    let isAboveZero = "hello" |>-> entropyAbove(0.0'f64)
    check isAboveZero

  test ">>= checkForSecrets — Ok passes through":
    ## Clean text flows through the gate unchanged
    let r = Result[string, string].ok("safe clean text") >>= checkForSecrets
    check r.isOk
    check r.get() == "safe clean text"

  test ">>= checkForSecrets — Err on secret":
    let r = Result[string, string].ok("sk-abcdefghijklmnopqrstuvwxyz") >>= checkForSecrets
    check r.isErr
    check "secret detected" in r.error

  test ">>= chain: two checkForSecrets gates":
    ## Both clean → Ok flows through both
    let r = Result[string, string].ok("no secrets here") >>= checkForSecrets >>= checkForSecrets
    check r.isOk

  test ">>= short-circuits on first Err":
    let r = Result[string, string].ok("sk-abcdefghijklmnopqrstuvwxyz") >>= checkForSecrets >>= checkForSecrets
    check r.isErr
