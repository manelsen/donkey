"""LiteLLM provider implementation for multi-provider support."""
import hashlib
import os
import secrets
import string
from typing import Any
import json_repair
import litellm
from litellm import acompletion
from loguru import logger
from nanobot.providers.base import LLMProvider, LLMResponse, ToolCallRequest
from nanobot.providers.registry import find_by_model, find_gateway
def _short_tool_id() -> str:
    """Generate a 9-char alphanumeric ID compatible with all providers (incl. Mistral)."""
    ...
class LiteLLMProvider(LLMProvider):
    """LLM provider using LiteLLM for multi-provider support.

Supports OpenRouter, Anthropic, OpenAI, Gemini, MiniMax, and many other providers through
a unified interface.  Provider-specific logic is driven by the registry
(see providers/registry.py) — no if-elif chains needed here."""
    def __init__(self, api_key: str | None = None, api_base: str | None = None, default_model: str = 'anthropic/claude-opus-4-5', extra_headers: dict[str, str] | None = None, provider_name: str | None = None):
        ...
    def _setup_env(self, api_key: str, api_base: str | None, model: str) -> None:
        """Set environment variables based on detected provider."""
        ...
    def _resolve_model(self, model: str) -> str:
        """Resolve model name by applying provider/gateway prefixes."""
        ...
    @staticmethod
    def _canonicalize_explicit_prefix(model: str, spec_name: str, canonical_prefix: str) -> str:
        """Normalize explicit provider prefixes like `github-copilot/...`."""
        ...
    def _supports_cache_control(self, model: str) -> bool:
        """Return True when the provider supports cache_control on content blocks."""
        ...
    def _apply_cache_control(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None) -> tuple[list[dict[str, Any]], list[dict[str, Any]] | None]:
        """Return copies of messages and tools with cache_control injected."""
        ...
    def _apply_model_overrides(self, model: str, kwargs: dict[str, Any]) -> None:
        """Apply model-specific parameter overrides from the registry."""
        ...
    @staticmethod
    def _extra_msg_keys(original_model: str, resolved_model: str) -> frozenset[str]:
        """Return provider-specific extra keys to preserve in request messages."""
        ...
    @staticmethod
    def _normalize_tool_call_id(tool_call_id: Any) -> Any:
        """Normalize tool_call_id to a provider-safe 9-char alphanumeric form."""
        ...
    @staticmethod
    def _sanitize_messages(messages: list[dict[str, Any]], extra_keys: frozenset[str] = frozenset()) -> list[dict[str, Any]]:
        """Strip non-standard keys and ensure assistant messages have a content key."""
        ...
    async def chat(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None = None, model: str | None = None, max_tokens: int = 4096, temperature: float = 0.7, reasoning_effort: str | None = None, tool_choice: str | dict[str, Any] | None = None) -> LLMResponse:
        """Send a chat completion request via LiteLLM.

Args:
    messages: List of message dicts with 'role' and 'content'.
    tools: Optional list of tool definitions in OpenAI format.
    model: Model identifier (e.g., 'anthropic/claude-sonnet-4-5').
    max_tokens: Maximum tokens in response.
    temperature: Sampling temperature.

Returns:
    LLMResponse with content and/or tool calls."""
        ...
    def _parse_response(self, response: Any) -> LLMResponse:
        """Parse LiteLLM response into our standard format."""
        ...
    def get_default_model(self) -> str:
        """Get the default model."""
        ...
