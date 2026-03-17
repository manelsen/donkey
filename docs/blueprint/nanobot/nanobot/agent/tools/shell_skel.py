"""Shell execution tool."""
import asyncio
import os
import re
from pathlib import Path
from typing import Any
from nanobot.agent.tools.base import Tool
class ExecTool(Tool):
    """Tool to execute shell commands."""
    def __init__(self, timeout: int = 60, working_dir: str | None = None, deny_patterns: list[str] | None = None, allow_patterns: list[str] | None = None, restrict_to_workspace: bool = False, path_append: str = ''):
        ...
    @property
    def name(self) -> str:
        ...
    _MAX_TIMEOUT = 600
    _MAX_OUTPUT = 10000
    @property
    def description(self) -> str:
        ...
    @property
    def parameters(self) -> dict[str, Any]:
        ...
    async def execute(self, command: str, working_dir: str | None = None, timeout: int | None = None, **kwargs: Any) -> str:
        ...
    def _guard_command(self, command: str, cwd: str) -> str | None:
        """Best-effort safety guard for potentially destructive commands."""
        ...
    @staticmethod
    def _extract_absolute_paths(command: str) -> list[str]:
        ...
