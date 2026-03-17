"""Session management for conversation history."""
import json
import shutil
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any
from loguru import logger
from nanobot.config.paths import get_legacy_sessions_dir
from nanobot.utils.helpers import ensure_dir, safe_filename
@dataclass
class Session:
    """A conversation session.

Stores messages in JSONL format for easy reading and persistence.

Important: Messages are append-only for LLM cache efficiency.
The consolidation process writes summaries to MEMORY.md/HISTORY.md
but does NOT modify the messages list or get_history() output."""
    key: str
    messages: list[dict[str, Any]] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.now)
    updated_at: datetime = field(default_factory=datetime.now)
    metadata: dict[str, Any] = field(default_factory=dict)
    last_consolidated: int = 0
    def add_message(self, role: str, content: str, **kwargs: Any) -> None:
        """Add a message to the session."""
        ...
    @staticmethod
    def _find_legal_start(messages: list[dict[str, Any]]) -> int:
        """Find first index where every tool result has a matching assistant tool_call."""
        ...
    def get_history(self, max_messages: int = 500) -> list[dict[str, Any]]:
        """Return unconsolidated messages for LLM input, aligned to a legal tool-call boundary."""
        ...
    def clear(self) -> None:
        """Clear all messages and reset session to initial state."""
        ...
class SessionManager:
    """Manages conversation sessions.

Sessions are stored as JSONL files in the sessions directory."""
    def __init__(self, workspace: Path):
        ...
    def _get_session_path(self, key: str) -> Path:
        """Get the file path for a session."""
        ...
    def _get_legacy_session_path(self, key: str) -> Path:
        """Legacy global session path (~/.nanobot/sessions/)."""
        ...
    def get_or_create(self, key: str) -> Session:
        """Get an existing session or create a new one.

Args:
    key: Session key (usually channel:chat_id).

Returns:
    The session."""
        ...
    def _load(self, key: str) -> Session | None:
        """Load a session from disk."""
        ...
    def save(self, session: Session) -> None:
        """Save a session to disk."""
        ...
    def invalidate(self, key: str) -> None:
        """Remove a session from the in-memory cache."""
        ...
    def list_sessions(self) -> list[dict[str, Any]]:
        """List all sessions.

Returns:
    List of session info dicts."""
        ...
