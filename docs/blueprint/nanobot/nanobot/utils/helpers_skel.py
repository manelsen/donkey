"""Utility functions for nanobot."""
import json
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Any
import tiktoken
def detect_image_mime(data: bytes) -> str | None:
    """Detect image MIME type from magic bytes, ignoring file extension."""
    ...
def ensure_dir(path: Path) -> Path:
    """Ensure directory exists, return it."""
    ...
def timestamp() -> str:
    """Current ISO timestamp."""
    ...
def current_time_str() -> str:
    """Human-readable current time with weekday and timezone, e.g. '2026-03-15 22:30 (Saturday) (CST)'."""
    ...
def safe_filename(name: str) -> str:
    """Replace unsafe path characters with underscores."""
    ...
def split_message(content: str, max_len: int = 2000) -> list[str]:
    """Split content into chunks within max_len, preferring line breaks.

Args:
    content: The text content to split.
    max_len: Maximum length per chunk (default 2000 for Discord compatibility).

Returns:
    List of message chunks, each within max_len."""
    ...
def build_assistant_message(content: str | None, tool_calls: list[dict[str, Any]] | None = None, reasoning_content: str | None = None, thinking_blocks: list[dict] | None = None) -> dict[str, Any]:
    """Build a provider-safe assistant message with optional reasoning fields."""
    ...
def estimate_prompt_tokens(messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None = None) -> int:
    """Estimate prompt tokens with tiktoken."""
    ...
def estimate_message_tokens(message: dict[str, Any]) -> int:
    """Estimate prompt tokens contributed by one persisted message."""
    ...
def estimate_prompt_tokens_chain(provider: Any, model: str | None, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None = None) -> tuple[int, str]:
    """Estimate prompt tokens via provider counter first, then tiktoken fallback."""
    ...
def sync_workspace_templates(workspace: Path, silent: bool = False) -> list[str]:
    """Sync bundled templates to workspace. Only creates missing files."""
    ...
