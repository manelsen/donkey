"""Subagent manager for background task execution."""
import asyncio
import json
import uuid
from pathlib import Path
from typing import Any
from loguru import logger
from nanobot.agent.skills import BUILTIN_SKILLS_DIR
from nanobot.agent.tools.filesystem import EditFileTool, ListDirTool, ReadFileTool, WriteFileTool
from nanobot.agent.tools.registry import ToolRegistry
from nanobot.agent.tools.shell import ExecTool
from nanobot.agent.tools.web import WebFetchTool, WebSearchTool
from nanobot.bus.events import InboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.config.schema import ExecToolConfig
from nanobot.providers.base import LLMProvider
from nanobot.utils.helpers import build_assistant_message
class SubagentManager:
    """Manages background subagent execution."""
    def __init__(self, provider: LLMProvider, workspace: Path, bus: MessageBus, model: str | None = None, web_search_config: 'WebSearchConfig | None' = None, web_proxy: str | None = None, exec_config: 'ExecToolConfig | None' = None, restrict_to_workspace: bool = False):
        ...
    async def spawn(self, task: str, label: str | None = None, origin_channel: str = 'cli', origin_chat_id: str = 'direct', session_key: str | None = None) -> str:
        """Spawn a subagent to execute a task in the background."""
        ...
    async def _run_subagent(self, task_id: str, task: str, label: str, origin: dict[str, str]) -> None:
        """Execute the subagent task and announce the result."""
        ...
    async def _announce_result(self, task_id: str, label: str, task: str, result: str, origin: dict[str, str], status: str) -> None:
        """Announce the subagent result to the main agent via the message bus."""
        ...
    def _build_subagent_prompt(self) -> str:
        """Build a focused system prompt for the subagent."""
        ...
    async def cancel_by_session(self, session_key: str) -> int:
        """Cancel all subagents for the given session. Returns count cancelled."""
        ...
    def get_running_count(self) -> int:
        """Return the number of currently running subagents."""
        ...
