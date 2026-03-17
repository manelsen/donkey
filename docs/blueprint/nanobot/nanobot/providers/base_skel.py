"""Base LLM provider interface."""
import asyncio
import json
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any
from loguru import logger
@dataclass
class ToolCallRequest:
    """A tool call request from the LLM."""
    id: str
    name: str
    arguments: dict[str, Any]
    provider_specific_fields: dict[str, Any] | None = None
    function_provider_specific_fields: dict[str, Any] | None = None
    def to_openai_tool_call(self) -> dict[str, Any]:
        """Serialize to an OpenAI-style tool_call payload."""
        ...
@dataclass
class LLMResponse:
    """Response from an LLM provider."""
    content: str | None
    tool_calls: list[ToolCallRequest] = field(default_factory=list)
    finish_reason: str = 'stop'
    usage: dict[str, int] = field(default_factory=dict)
    reasoning_content: str | None = None
    thinking_blocks: list[dict] | None = None
    @property
    def has_tool_calls(self) -> bool:
        """Check if response contains tool calls."""
        ...
@dataclass(frozen=True)
class GenerationSettings:
    """Default generation parameters for LLM calls.

Stored on the provider so every call site inherits the same defaults
without having to pass temperature / max_tokens / reasoning_effort
through every layer.  Individual call sites can still override by
passing explicit keyword arguments to chat() / chat_with_retry()."""
    temperature: float = 0.7
    max_tokens: int = 4096
    reasoning_effort: str | None = None
class LLMProvider(ABC):
    """Abstract base class for LLM providers.

Implementations should handle the specifics of each provider's API
while maintaining a consistent interface."""
    _CHAT_RETRY_DELAYS = (1, 2, 4)
    _TRANSIENT_ERROR_MARKERS = ('429', 'rate limit', '500', '502', '503', '504', 'overloaded', 'timeout', 'timed out', 'connection', 'server error', 'temporarily unavailable')
    _IMAGE_UNSUPPORTED_MARKERS = ('image_url is only supported', 'does not support image', 'images are not supported', 'image input is not supported', 'image_url is not supported', 'unsupported image input')
    _SENTINEL = object()
    def __init__(self, api_key: str | None = None, api_base: str | None = None):
        ...
    @staticmethod
    def _sanitize_empty_content(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Replace empty text content that causes provider 400 errors.

Empty content can appear when MCP tools return nothing. Most providers
reject empty-string content or empty text blocks in list content."""
        ...
    @staticmethod
    def _sanitize_request_messages(messages: list[dict[str, Any]], allowed_keys: frozenset[str]) -> list[dict[str, Any]]:
        """Keep only provider-safe message keys and normalize assistant content."""
        ...
    @abstractmethod
    async def chat(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None = None, model: str | None = None, max_tokens: int = 4096, temperature: float = 0.7, reasoning_effort: str | None = None, tool_choice: str | dict[str, Any] | None = None) -> LLMResponse:
        """Send a chat completion request.

Args:
    messages: List of message dicts with 'role' and 'content'.
    tools: Optional list of tool definitions.
    model: Model identifier (provider-specific).
    max_tokens: Maximum tokens in response.
    temperature: Sampling temperature.
    tool_choice: Tool selection strategy ("auto", "required", or specific tool dict).

Returns:
    LLMResponse with content and/or tool calls."""
        ...
    @classmethod
    def _is_transient_error(cls, content: str | None) -> bool:
        ...
    @classmethod
    def _is_image_unsupported_error(cls, content: str | None) -> bool:
        ...
    @staticmethod
    def _strip_image_content(messages: list[dict[str, Any]]) -> list[dict[str, Any]] | None:
        """Replace image_url blocks with text placeholder. Returns None if no images found."""
        ...
    async def _safe_chat(self, **kwargs: Any) -> LLMResponse:
        """Call chat() and convert unexpected exceptions to error responses."""
        ...
    async def chat_with_retry(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None = None, model: str | None = None, max_tokens: object = _SENTINEL, temperature: object = _SENTINEL, reasoning_effort: object = _SENTINEL, tool_choice: str | dict[str, Any] | None = None) -> LLMResponse:
        """Call chat() with retry on transient provider failures.

Parameters default to ``self.generation`` when not explicitly passed,
so callers no longer need to thread temperature / max_tokens /
reasoning_effort through every layer."""
        ...
    @abstractmethod
    def get_default_model(self) -> str:
        """Get the default model for this provider."""
        ...
