"""Tool registry for dynamic tool management."""
from typing import Any
from nanobot.agent.tools.base import Tool
class ToolRegistry:
    """Registry for agent tools.

Allows dynamic registration and execution of tools."""
    def __init__(self):
        ...
    def register(self, tool: Tool) -> None:
        """Register a tool."""
        ...
    def unregister(self, name: str) -> None:
        """Unregister a tool by name."""
        ...
    def get(self, name: str) -> Tool | None:
        """Get a tool by name."""
        ...
    def has(self, name: str) -> bool:
        """Check if a tool is registered."""
        ...
    def get_definitions(self) -> list[dict[str, Any]]:
        """Get all tool definitions in OpenAI format."""
        ...
    async def execute(self, name: str, params: dict[str, Any]) -> str:
        """Execute a tool by name with given parameters."""
        ...
    @property
    def tool_names(self) -> list[str]:
        """Get list of registered tool names."""
        ...
    def __len__(self) -> int:
        ...
    def __contains__(self, name: str) -> bool:
        ...
