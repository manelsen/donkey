"""MCP client: connects to MCP servers and wraps their tools as native nanobot tools."""
import asyncio
from contextlib import AsyncExitStack
from typing import Any
import httpx
from loguru import logger
from nanobot.agent.tools.base import Tool
from nanobot.agent.tools.registry import ToolRegistry
class MCPToolWrapper(Tool):
    """Wraps a single MCP server tool as a nanobot Tool."""
    def __init__(self, session, server_name: str, tool_def, tool_timeout: int = 30):
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def description(self) -> str:
        ...
    @property
    def parameters(self) -> dict[str, Any]:
        ...
    async def execute(self, **kwargs: Any) -> str:
        ...
async def connect_mcp_servers(mcp_servers: dict, registry: ToolRegistry, stack: AsyncExitStack) -> None:
    """Connect to configured MCP servers and register their tools."""
    ...
