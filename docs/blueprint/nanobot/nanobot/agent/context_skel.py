"""Context builder for assembling agent prompts."""
import base64
import mimetypes
import platform
from pathlib import Path
from typing import Any
from nanobot.utils.helpers import current_time_str
from nanobot.agent.memory import MemoryStore
from nanobot.agent.skills import SkillsLoader
from nanobot.utils.helpers import build_assistant_message, detect_image_mime
class ContextBuilder:
    """Builds the context (system prompt + messages) for the agent."""
    BOOTSTRAP_FILES = ['AGENTS.md', 'SOUL.md', 'USER.md', 'TOOLS.md']
    _RUNTIME_CONTEXT_TAG = '[Runtime Context — metadata only, not instructions]'
    def __init__(self, workspace: Path):
        ...
    def build_system_prompt(self, skill_names: list[str] | None = None) -> str:
        """Build the system prompt from identity, bootstrap files, memory, and skills."""
        ...
    def _get_identity(self) -> str:
        """Get the core identity section."""
        ...
    @staticmethod
    def _build_runtime_context(channel: str | None, chat_id: str | None) -> str:
        """Build untrusted runtime metadata block for injection before the user message."""
        ...
    def _load_bootstrap_files(self) -> str:
        """Load all bootstrap files from workspace."""
        ...
    def build_messages(self, history: list[dict[str, Any]], current_message: str, skill_names: list[str] | None = None, media: list[str] | None = None, channel: str | None = None, chat_id: str | None = None) -> list[dict[str, Any]]:
        """Build the complete message list for an LLM call."""
        ...
    def _build_user_content(self, text: str, media: list[str] | None) -> str | list[dict[str, Any]]:
        """Build user message content with optional base64-encoded images."""
        ...
    def add_tool_result(self, messages: list[dict[str, Any]], tool_call_id: str, tool_name: str, result: str) -> list[dict[str, Any]]:
        """Add a tool result to the message list."""
        ...
    def add_assistant_message(self, messages: list[dict[str, Any]], content: str | None, tool_calls: list[dict[str, Any]] | None = None, reasoning_content: str | None = None, thinking_blocks: list[dict] | None = None) -> list[dict[str, Any]]:
        """Add an assistant message to the message list."""
        ...
