"""Direct OpenAI-compatible provider — bypasses LiteLLM."""
from __future__ import annotations
import uuid
from typing import Any
import json_repair
from openai import AsyncOpenAI
from nanobot.providers.base import LLMProvider, LLMResponse, ToolCallRequest
class CustomProvider(LLMProvider):
    def __init__(self, api_key: str = 'no-key', api_base: str = 'http://localhost:8000/v1', default_model: str = 'default'):
        ...
    async def chat(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None = None, model: str | None = None, max_tokens: int = 4096, temperature: float = 0.7, reasoning_effort: str | None = None, tool_choice: str | dict[str, Any] | None = None) -> LLMResponse:
        ...
    def _parse(self, response: Any) -> LLMResponse:
        ...
    def get_default_model(self) -> str:
        ...
