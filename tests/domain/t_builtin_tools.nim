import unittest
import std/[json, strutils]
import donkey/config/types
import donkey/domain/builtin_tools

suite "web_fetch tool metadata":

  test "name and description are non-empty":
    check WebFetchToolName.len > 0
    check WebFetchToolDescription.len > 0

  test "schema is valid JSON with required url":
    let j = parseJson(WebFetchToolSchema)
    check j["type"].getStr() == "object"
    check j["required"][0].getStr() == "url"

suite "current_time tool metadata":

  test "name and description are non-empty":
    check CurrentTimeToolName.len > 0
    check CurrentTimeToolDescription.len > 0

  test "schema is valid JSON":
    let j = parseJson(CurrentTimeToolSchema)
    check j["type"].getStr() == "object"

suite "truncateBody":

  test "short content returned as-is":
    check truncateBody("hello", 100) == "hello"

  test "long content truncated with marker":
    let r = truncateBody("abcdefghij", 5)
    check r.startsWith("abcde")
    check "[..." in r

  test "HardMaxChars caps output regardless of argument":
    let big = "x".repeat(HardMaxChars + 500)
    let r   = truncateBody(big, HardMaxChars + 500)
    check r.len < HardMaxChars + 30

suite "isPrivateUrl":

  test "localhost is private":
    check isPrivateUrl("http://localhost/")
    check isPrivateUrl("http://localhost:8080/api")

  test "127.x.x.x is private":
    check isPrivateUrl("http://127.0.0.1/")
    check isPrivateUrl("http://127.1.2.3/path")

  test "192.168.x.x is private":
    check isPrivateUrl("http://192.168.1.100/")

  test "10.x.x.x is private":
    check isPrivateUrl("http://10.0.0.1/")

  test "169.254.x.x is private (link-local / cloud metadata)":
    check isPrivateUrl("http://169.254.169.254/latest/meta-data/")

  test "172.16-31.x.x is private":
    check isPrivateUrl("http://172.16.0.1/")
    check isPrivateUrl("http://172.31.255.255/")

  test "172.32+ and 172.15 are NOT private":
    check not isPrivateUrl("http://172.32.0.1/")
    check not isPrivateUrl("http://172.15.0.1/")

  test "non-numeric 172 labels do not raise":
    check not isPrivateUrl("http://172.example.com/")
    check not isPrivateUrl("http://172.99999999999999999999.example/")
    check not isPrivateUrl("http://172./")

  test "public URLs are not private":
    check not isPrivateUrl("https://example.com/")
    check not isPrivateUrl("https://api.github.com/users")

  test "hostname containing '10' in name is not private":
    check not isPrivateUrl("http://site10.example.com/")

  test "hostname containing '127' in path is not private":
    check not isPrivateUrl("https://example.com/ref/127")

  test "userinfo and @ in path cannot spoof the authority":
    check isPrivateUrl("http://127.0.0.1:8080/admin@example.com")
    check isPrivateUrl("http://127.0.0.1:8080/admin?x=@example.com")
    check isPrivateUrl("http://user:pass@127.0.0.1/")
    check extractUrlHost("http://127.0.0.1:8080/admin@example.com") == "127.0.0.1"
    check extractUrlHost("https://user:pass@example.com/x") == "example.com"
    check not isPrivateUrl("https://example.com/@")

  test "IPv6 loopback and mapped addresses are private":
    check isPrivateUrl("http://[::1]/")
    check isPrivateUrl("http://[::ffff:127.0.0.1]/")
    check extractUrlHost("http://[::1]:8080/") == "::1"

  test "extractUrlPath keeps @ in the path":
    check extractUrlPath("https://example.com/admin@example.com?x=1") ==
      "/admin@example.com"

suite "web allowlist":

  test "parseWebAllowlist trims and normalizes hosts":
    check parseWebAllowlist(" example.com, api.github.com ,,Docs.Nim-lang.org ") ==
      @["example.com", "api.github.com", "docs.nim-lang.org"]

  test "isAllowedPublicUrl allows public URLs when allowlist empty":
    check isAllowedPublicUrl("https://example.com/docs", @[])

  test "isAllowedPublicUrl blocks public URL outside allowlist":
    check not isAllowedPublicUrl("https://example.com/docs", @["api.github.com"])

  test "isAllowedPublicUrl accepts subdomains of allowed host":
    check isAllowedPublicUrl("https://docs.nim-lang.org/manual", @["nim-lang.org"])

  test "buildUrlAccessError mentions allowlist env var":
    let msg = buildUrlAccessError("https://example.com/docs", @["api.github.com"])
    check msg.contains(WebAllowlistEnvVar)
    check msg.contains("example.com")

  test "matchesWebAccessRule enforces path prefix":
    let rule = WebAccessRule(host: "api.github.com", pathPrefix: "/repos/")
    check matchesWebAccessRule("https://api.github.com/repos/openai/openai", rule)
    check not matchesWebAccessRule("https://api.github.com/users/openai", rule)

  test "rule-based allowlist prefers explicit rules":
    let rules = @[WebAccessRule(host: "docs.nim-lang.org", pathPrefix: "/manual")]
    check isAllowedPublicUrl("https://docs.nim-lang.org/manual.html", rules, @["example.com"])
    check not isAllowedPublicUrl("https://docs.nim-lang.org/tutorials.html", rules, @["docs.nim-lang.org"])
