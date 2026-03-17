"""Spawn tool for creating background subagents."""
from typing import TYPE_CHECKING, Any
from nanobot.agent.tools.base import Tool
class SpawnTool(Tool):
    """Tool to spawn a subagent for background task execution."""
    def __init__(self, manager: 'SubagentManager'):
        ...
    def set_context(self, channel: str, chat_id: str) -> None:
        """Set the origin context for subagent announcements."""
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
    async def execute(self, task: str, label: str | None = None, **kwargs: Any) -> str:
        """Spawn a subagent to execute the given task."""
        ...
