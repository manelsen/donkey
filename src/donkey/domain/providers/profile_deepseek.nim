## profile_deepseek.nim — DeepSeek's own API (api.deepseek.com).
##
## The OpenAI dialect plus one must-echo rule: an assistant turn sent back
## without `reasoning_content` makes DeepSeek answer 400 on a tool round, so
## every assistant turn carries the reasoning it came with, or " " (hermes
## lists DeepSeek with Kimi and MiMo in its must-echo tier,
## `agent/message_sanitization.py`). Pure data.

import ./compat
import ./openai_pure

const DeepSeekEndpointDefault* = "https://api.deepseek.com/v1/chat/completions"

func deepseekCompatProfileAt*(endpoint: string): CompatProfile =
  result = defaultOpenAiProfile(endpoint = endpoint, id = "deepseek")
  result.quirks.echoReasoningContent = true

func deepseekCompatProfile*(): CompatProfile =
  deepseekCompatProfileAt(DeepSeekEndpointDefault)
