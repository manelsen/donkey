import unittest
import donkey/core/telegram_format
import donkey/domain/text_format

suite "Telegram Formatting":

  test "escapes basic HTML entities":
    check escapeHtml("A < B & C > D") == "A &lt; B &amp; C &gt; D"

  test "converts bold":
    check markdownToTelegramHtml("Hello **world**") == "Hello <b>world</b>"
    check markdownToTelegramHtml("Hello __world__") == "Hello <b>world</b>"

  test "converts italic":
    check markdownToTelegramHtml("Hello *world*") == "Hello <i>world</i>"
    check markdownToTelegramHtml("Hello _world_") == "Hello <i>world</i>"

  test "converts inline code":
    check markdownToTelegramHtml("Use `code` here") == "Use <code>code</code> here"

  test "converts triple backtick code block":
    check markdownToTelegramHtml("```\nprint('hi')\n```") == "<pre>print('hi')\n</pre>"
    check markdownToTelegramHtml("```python\nprint('hi')\n```") == "<pre>print('hi')\n</pre>"

  test "converts single line blockquote":
    check markdownToTelegramHtml("> hello") == "<blockquote>hello</blockquote>"

  test "converts multiline blockquote":
    let md = "> line 1\n> line 2"
    check markdownToTelegramHtml(md) == "<blockquote>line 1\nline 2</blockquote>"

  test "converts mixed formatting":
    let md = "**bold** and *italic* and `code`"
    check markdownToTelegramHtml(md) == "<b>bold</b> and <i>italic</i> and <code>code</code>"

  test "converts links":
    check markdownToTelegramHtml("[Google](https://google.com)") == "<a href=\"https://google.com\">Google</a>"

  test "handles complex reasoning block":
    let md = "> Step 1: Thinking...\n> Step 2: More thinking.\n\nFinal answer is **42**."
    let expected = "<blockquote>Step 1: Thinking...\nStep 2: More thinking.</blockquote>\n\nFinal answer is <b>42</b>."
    check markdownToTelegramHtml(md) == expected
