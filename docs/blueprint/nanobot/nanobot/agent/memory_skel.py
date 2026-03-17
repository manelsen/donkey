"""Memory system for persistent agent memory."""
from __future__ import annotations
import asyncio
import json
import weakref
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING, Any, Callable
from loguru import logger
from nanobot.utils.helpers import ensure_dir, estimate_message_tokens, estimate_prompt_tokens_chain
def _ensure_text(value: Any) -> str:
    """Normalize tool-call payload values to text for file storage."""
    ...
def _normalize_save_memory_args(args: Any) -> dict[str, Any] | None:
    """Normalize provider tool-call arguments to the expected dict shape."""
    ...
def _is_tool_choice_unsupported(content: str | None) -> bool:
    """Detect provider errors caused by forced tool_choice being unsupported."""
    ...
class MemoryStore:
    """Two-layer memory: MEMORY.md (long-term facts) + HISTORY.md (grep-searchable log)."""
    _MAX_FAILURES_BEFORE_RAW_ARCHIVE = 3
    def __init__(self, workspace: Path):
        ...
    def read_long_term(self) -> str:
        ...
    def write_long_term(self, content: str) -> None:
        ...
    def append_history(self, entry: str) -> None:
        ...
    def get_memory_context(self) -> str:
        ...
    @staticmethod
    def _format_messages(messages: list[dict]) -> str:
        ...
    async def consolidate(self, messages: list[dict], provider: LLMProvider, model: str) -> bool:
        """Consolidate the provided message chunk into MEMORY.md + HISTORY.md."""
        ...
    def _fail_or_raw_archive(self, messages: list[dict]) -> bool:
        """Increment failure count; after threshold, raw-archive messages and return True."""
        ...
    def _raw_archive(self, messages: list[dict]) -> None:
        """Fallback: dump raw messages to HISTORY.md without LLM summarization."""
        ...
class MemoryConsolidator:
    """Owns consolidation policy, locking, and session offset updates."""
    _MAX_CONSOLIDATION_ROUNDS = 5
    def __init__(self, workspace: Path, provider: LLMProvider, model: str, sessions: SessionManager, context_window_tokens: int, build_messages: Callable[..., list[dict[str, Any]]], get_tool_definitions: Callable[[], list[dict[str, Any]]]):
        ...
    def get_lock(self, session_key: str) -> asyncio.Lock:
        """Return the shared consolidation lock for one session."""
        ...
    async def consolidate_messages(self, messages: list[dict[str, object]]) -> bool:
        """Archive a selected message chunk into persistent memory."""
        ...
    def pick_consolidation_boundary(self, session: Session, tokens_to_remove: int) -> tuple[int, int] | None:
        """Pick a user-turn boundary that removes enough old prompt tokens."""
        ...
    def estimate_session_prompt_tokens(self, session: Session) -> tuple[int, str]:
        """Estimate current prompt size for the normal session history view."""
        ...
    async def archive_messages(self, messages: list[dict[str, object]]) -> bool:
        """Archive messages with guaranteed persistence (retries until raw-dump fallback)."""
        ...
    async def maybe_consolidate_by_tokens(self, session: Session) -> None:
        """Loop: archive old messages until prompt fits within half the context window."""
        ...
