"""Azure OpenAI provider implementation with API version 2024-10-21."""
from __future__ import annotations
import uuid
from typing import Any
from urllib.parse import urljoin
import httpx
import json_repair
from nanobot.providers.base import LLMProvider, LLMResponse, ToolCallRequest
class AzureOpenAIProvider(LLMProvider):
    """Azure OpenAI provider with API version 2024-10-21 compliance.

Features:
- Hardcoded API version 2024-10-21
- Uses model field as Azure deployment name in URL path
- Uses api-key header instead of Authorization Bearer
- Uses max_completion_tokens instead of max_tokens
- Direct HTTP calls, bypasses LiteLLM"""
    def __init__(self, api_key: str = '', api_base: str = '', default_model: str = 'gpt-5.2-chat'):
        ...
    def _build_chat_url(self, deployment_name: str) -> str:
        """Build the Azure OpenAI chat completions URL."""
        ...
    def _build_headers(self) -> dict[str, str]:
        """Build headers for Azure OpenAI API with api-key header."""
        ...
    @staticmethod
    def _supports_temperature(deployment_name: str, reasoning_effort: str | None = None) -> bool:
        """Return True when temperature is likely supported for this deployment."""
        ...
    def _prepare_request_payload(self, deployment_name: str, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None = None, max_tokens: int = 4096, temperature: float = 0.7, reasoning_effort: str | None = None, tool_choice: str | dict[str, Any] | None = None) -> dict[str, Any]:
        """Prepare the request payload with Azure OpenAI 2024-10-21 compliance."""
        ...
    async def chat(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None = None, model: str | None = None, max_tokens: int = 4096, temperature: float = 0.7, reasoning_effort: str | None = None, tool_choice: str | dict[str, Any] | None = None) -> LLMResponse:
        """Send a chat completion request to Azure OpenAI.

Args:
    messages: List of message dicts with 'role' and 'content'.
    tools: Optional list of tool definitions in OpenAI format.
    model: Model identifier (used as deployment name).
    max_tokens: Maximum tokens in response (mapped to max_completion_tokens).
    temperature: Sampling temperature.
    reasoning_effort: Optional reasoning effort parameter.

Returns:
    LLMResponse with content and/or tool calls."""
        ...
    def _parse_response(self, response: dict[str, Any]) -> LLMResponse:
        """Parse Azure OpenAI response into our standard format."""
        ...
    def get_default_model(self) -> str:
        """Get the default model (also used as default deployment name)."""
        ...
