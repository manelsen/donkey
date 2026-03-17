"""Agent loop: the core processing engine."""
from __future__ import annotations
import asyncio
import json
import os
import re
import sys
from contextlib import AsyncExitStack
from pathlib import Path
from typing import TYPE_CHECKING, Any, Awaitable, Callable
from loguru import logger
from nanobot.agent.context import ContextBuilder
from nanobot.agent.memory import MemoryConsolidator
from nanobot.agent.subagent import SubagentManager
from nanobot.agent.tools.cron import CronTool
from nanobot.agent.skills import BUILTIN_SKILLS_DIR
from nanobot.agent.tools.filesystem import EditFileTool, ListDirTool, ReadFileTool, WriteFileTool
from nanobot.agent.tools.message import MessageTool
from nanobot.agent.tools.registry import ToolRegistry
from nanobot.agent.tools.shell import ExecTool
from nanobot.agent.tools.spawn import SpawnTool
from nanobot.agent.tools.web import WebFetchTool, WebSearchTool
from nanobot.bus.events import InboundMessage, OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.providers.base import LLMProvider
from nanobot.session.manager import Session, SessionManager
class AgentLoop:
    """The agent loop is the core processing engine.

It:
1. Receives messages from the bus
2. Builds context with history, memory, skills
3. Calls the LLM
4. Executes tool calls
5. Sends responses back"""
    _TOOL_RESULT_MAX_CHARS = 16000
    def __init__(self, bus: MessageBus, provider: LLMProvider, workspace: Path, model: str | None = None, max_iterations: int = 40, context_window_tokens: int = 65536, web_search_config: WebSearchConfig | None = None, web_proxy: str | None = None, exec_config: ExecToolConfig | None = None, cron_service: CronService | None = None, restrict_to_workspace: bool = False, session_manager: SessionManager | None = None, mcp_servers: dict | None = None, channels_config: ChannelsConfig | None = None):
        ...
    def _register_default_tools(self) -> None:
        """Register the default set of tools."""
        ...
    async def _connect_mcp(self) -> None:
        """Connect to configured MCP servers (one-time, lazy)."""
        ...
    def _set_tool_context(self, channel: str, chat_id: str, message_id: str | None = None) -> None:
        """Update context for all tools that need routing info."""
        ...
    @staticmethod
    def _strip_think(text: str | None) -> str | None:
        """Remove <think>…</think> blocks that some models embed in content."""
        ...
    @staticmethod
    def _tool_hint(tool_calls: list) -> str:
        """Format tool calls as concise hint, e.g. 'web_search("query")'."""
        ...
    async def _run_agent_loop(self, initial_messages: list[dict], on_progress: Callable[..., Awaitable[None]] | None = None) -> tuple[str | None, list[str], list[dict]]:
        """Run the agent iteration loop."""
        ...
    async def run(self) -> None:
        """Run the agent loop, dispatching messages as tasks to stay responsive to /stop."""
        ...
    async def _handle_stop(self, msg: InboundMessage) -> None:
        """Cancel all active tasks and subagents for the session."""
        ...
    async def _handle_restart(self, msg: InboundMessage) -> None:
        """Restart the process in-place via os.execv."""
        ...
    async def _dispatch(self, msg: InboundMessage) -> None:
        """Process a message under the global lock."""
        ...
    async def close_mcp(self) -> None:
        """Drain pending background archives, then close MCP connections."""
        ...
    def _schedule_background(self, coro) -> None:
        """Schedule a coroutine as a tracked background task (drained on shutdown)."""
        ...
    def stop(self) -> None:
        """Stop the agent loop."""
        ...
    async def _process_message(self, msg: InboundMessage, session_key: str | None = None, on_progress: Callable[[str], Awaitable[None]] | None = None) -> OutboundMessage | None:
        """Process a single inbound message and return the response."""
        ...
    def _save_turn(self, session: Session, messages: list[dict], skip: int) -> None:
        """Save new-turn messages into session, truncating large tool results."""
        ...
    async def process_direct(self, content: str, session_key: str = 'cli:direct', channel: str = 'cli', chat_id: str = 'direct', on_progress: Callable[[str], Awaitable[None]] | None = None) -> str:
        """Process a message directly (for CLI or cron usage)."""
        ...
