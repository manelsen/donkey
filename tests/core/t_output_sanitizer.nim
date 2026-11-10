## Output sanitizer unit tests.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/core/output_sanitizer
import donkey/core/security/secret_scan

suite "output_sanitizer — stripTagPair":

  test "removes content between open/close tags":
    let r = stripTagPair("<thinking>", "</thinking>", "hello <thinking>secret</thinking> world")
    check r == "hello  world"

  test "multiple blocks are all removed":
    let r = stripTagPair("<thinking>", "</thinking>", "<thinking>A</thinking>text<thinking>B</thinking>")
    check r == "text"

  test "no matching tags leaves text unchanged":
    let r = stripTagPair("<thinking>", "</thinking>", "no tags here")
    check r == "no tags here"

  test "empty string returns empty string":
    let r = stripTagPair("<thinking>", "</thinking>", "")
    check r == ""

  test "tag with no content inside is stripped":
    let r = stripTagPair("<thinking>", "</thinking>", "before<thinking></thinking>after")
    check r == "beforeafter"

  test "missing close tag strips everything from open tag onward":
    let r = stripTagPair("<thinking>", "</thinking>", "before<thinking>unterminated")
    check r == "before"

  test "adjacent blocks with text between are handled":
    let r = stripTagPair("<x>", "</x>", "a<x>1</x>b<x>2</x>c")
    check r == "abc"

suite "output_sanitizer — stripTagPair pipeops |>->":

  test "|>-> works for last-arg piping":
    let r = "prefix <thinking>hidden</thinking> suffix" |>-> stripTagPair("<thinking>", "</thinking>")
    check r == "prefix  suffix"

  test "|>-> chain: two different tag types":
    let r = ("a<x>1</x>b<y>2</y>c" |>-> stripTagPair("<x>", "</x>")) |>->
      stripTagPair("<y>", "</y>")
    check r == "abc"

suite "output_sanitizer — stripThoughtTags":

  test "strips thinking tags":
    let r = stripThoughtTags("Answer: <thinking>inner thought</thinking>42")
    check r == "Answer: 42"

  test "strips think tags":
    let r = stripThoughtTags("Result: <think>reasoning here</think>yes")
    check r == "Result: yes"

  test "strips both thinking and think tags":
    let r = stripThoughtTags("<thinking>A</thinking>mid<think>B</think>end")
    check r == "midend"

  test "no tags leaves text unchanged":
    check stripThoughtTags("clean response") == "clean response"

  test "empty string returns empty string":
    check stripThoughtTags("") == ""

  test "nested-looking tags are handled sequentially":
    ## Outer <thinking> stripped first, leaving no inner
    let r = stripThoughtTags("<thinking>outer <think>inner</think></thinking>rest")
    check r == "rest"

  test "thought block at start of text is stripped":
    let r = stripThoughtTags("<thinking>preamble</thinking>visible")
    check r == "visible"

  test "thought block at end of text is stripped":
    let r = stripThoughtTags("visible<thinking>epilogue</thinking>")
    check r == "visible"

suite "output_sanitizer — stripThoughtTags pipeops |>":

  test "|> chaining strips thought content":
    let r = "before <thinking>hidden</thinking> after" |> stripThoughtTags
    check "hidden" notin r
    check "before" in r
    check "after" in r

  test "|> on clean text returns text unchanged":
    let r = "plain answer" |> stripThoughtTags
    check r == "plain answer"

suite "output_sanitizer — maskSecrets":

  test "masks known-prefix OpenAI-style key":
    let r = maskSecrets("key: sk-abcdefghijklmnopqrstuvwxyz1234")
    check "[REDACTED]" in r
    check "sk-abcde" notin r

  test "masks Anthropic key":
    let r = maskSecrets("set SK=sk-ant-api03-abcdefghijklmnopqrst")
    check "[REDACTED]" in r

  test "masks high-entropy token":
    let r = maskSecrets("config: sK3rT9pQwX2mNvL5hR8aB4cE7gF1dH6j")
    check "[REDACTED]" in r

  test "leaves clean short text unchanged":
    let r = maskSecrets("the quick brown fox")
    check r == "the quick brown fox"

  test "preserves delimiters around masked tokens":
    let r = maskSecrets("prefix sk-abcdefghijklmnopqrstuvwxyz1234 suffix")
    check r.startsWith("prefix ")
    check r.endsWith(" suffix")
    check "[REDACTED]" in r

  test "empty string returns empty string":
    check maskSecrets("") == ""

suite "output_sanitizer — maskSecrets pipeops |>":

  test "|> maskSecrets — unary pipe works":
    let r = "token sk-abcdefghijklmnopqrstuvwxyz1234" |> maskSecrets
    check "[REDACTED]" in r

  test "|> maskSecrets — clean text passes through":
    let r = "no secrets here" |> maskSecrets
    check r == "no secrets here"

suite "output_sanitizer — cleanResponse":

  test "strips thought tags and masks secrets":
    let r = cleanResponse("<thinking>plan: sk-abcdefghijklmnopq1234567</thinking>The answer is 42.")
    check "thinking" notin r
    check "sk-abcde" notin r
    check "42" in r

  test "clean response passes through unchanged":
    let r = cleanResponse("Hello! How can I help you today?")
    check r == "Hello! How can I help you today?"

  test "empty string returns empty string":
    check cleanResponse("") == ""

  test "strips thought tags even without secrets":
    let r = cleanResponse("<thinking>internal reasoning</thinking>Final answer.")
    check r == "Final answer."

  test "masks secrets even without thought tags":
    let r = cleanResponse("Here is your key: sk-abcdefghijklmnopqrstuvwxyz1234")
    check "[REDACTED]" in r
    check "sk-abcde" notin r

  test "both operations applied in order":
    ## Secret inside a thought tag: after stripping, no secret in output
    let r = cleanResponse("text<thinking>sk-abcdefghijklmnopqrst</thinking>end")
    check "thinking" notin r
    check "sk-abcde" notin r
    check "end" in r

suite "output_sanitizer — cleanResponse pipeops":

  test "|> cleanResponse — unary pipe works":
    let r = "normal text" |> cleanResponse
    check r == "normal text"

  test "|> chained: stripThoughtTags |> maskSecrets equals cleanResponse":
    let input = "response <thinking>internal</thinking> with key: sk-abcdefghijklmnopqrst1234"
    let direct = input |> cleanResponse
    let chained = input |> stripThoughtTags |> maskSecrets
    check direct == chained

  test ">>= cleanResponse gate: ok passes through after clean":
    let r = Result[string, string].ok("safe text") >>= checkForSecrets
    check r.isOk
    check r.get() == "safe text"

  test ">>= pipeline: clean then check":
    ## cleanResponse masks secrets so checkForSecrets should pass
    let input = "sk-abcdefghijklmnopqrstuvwxyz1234"
    let cleaned = input |> cleanResponse
    let r = Result[string, string].ok(cleaned) >>= checkForSecrets
    ## After masking, [REDACTED] should not trigger secret detection
    check r.isOk

suite "output_sanitizer — safeStreamPrefix":
  test "holds back an unterminated credential prefix":
    check safeStreamPrefix("hello sk-abc") == "hello "

  test "emits complete text when the tail is not credential-like":
    check safeStreamPrefix("hello world") == "hello world"

  test "holds back a whole credential-looking chunk":
    check safeStreamPrefix("sk-abc") == ""

  test "does not hold back after a delimiter":
    check safeStreamPrefix("hello sk-abc ") == "hello sk-abc "

  test "empty input is empty":
    check safeStreamPrefix("") == ""

  test "holds back a partial thought tag":
    check safeStreamPrefix("ok <thin") == "ok "

  test "holds back an unterminated thought tag":
    check safeStreamPrefix("ok <thinking>secret") == "ok "

  test "holds back the value after Bearer":
    check safeStreamPrefix("Bearer abc") == "Bearer "

  test "holds back the value after Bearer with repeated delimiters":
    check safeStreamPrefix("Bearer\n\nabc") == "Bearer\n\n"
    check safeStreamPrefix("Bearer  abc") == "Bearer  "

  test "holds back a credential after an assignment separator":
    check safeStreamPrefix("api_key=sk-abcdefgh") == ""
    check safeStreamPrefix("x api_key=sk-abcdefgh") == "x "

  test "masks a short credential after an assignment separator":
    check cleanResponse("api_key=sk-abcdefgh") == "[REDACTED]"
    check cleanResponse("API_KEY=sk-abcdefgh") == "[REDACTED]"

  test "preserves URLs and hex hashes":
    check cleanResponse("https://github.com/manelsen/donkey") == "https://github.com/manelsen/donkey"
    let hash = "57afdf4a15e4d7bb6cc2dd1d2908b78543269b39"
    check cleanResponse(hash) == hash

  test "keeps ordinary auth prose intact":
    check cleanResponse("use Bearer auth") == "use Bearer auth"
    check cleanResponse("Authorization: Bearer abc123") == "Authorization: Bearer abc123"

  test "keeps locale-like assignments intact":
    check cleanResponse("locale=sk-SK") == "locale=sk-SK"
    check cleanResponse("lang:sk-SK") == "lang:sk-SK"
    check cleanResponse("x=AKIAN") == "x=AKIAN"

  test "short non-secret tokens are not held":
    check safeStreamPrefix("sk") == "sk"

  test "closed thought tags are removed by the caller's cleanResponse":
    check cleanResponse("ok <thinking>secret</thinking>done") == "ok done"
