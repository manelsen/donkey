import unittest
import std/[json, strutils]
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

  test "public URLs are not private":
    check not isPrivateUrl("https://example.com/")
    check not isPrivateUrl("https://api.github.com/users")

  test "hostname containing '10' in name is not private":
    check not isPrivateUrl("http://site10.example.com/")

  test "hostname containing '127' in path is not private":
    check not isPrivateUrl("https://example.com/ref/127")
