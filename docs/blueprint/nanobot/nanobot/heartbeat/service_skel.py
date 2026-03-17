"""Heartbeat service - periodic agent wake-up to check for tasks."""
from __future__ import annotations
import asyncio
from pathlib import Path
from typing import TYPE_CHECKING, Any, Callable, Coroutine
from loguru import logger
class HeartbeatService:
    """Periodic heartbeat service that wakes the agent to check for tasks.

Phase 1 (decision): reads HEARTBEAT.md and asks the LLM — via a virtual
tool call — whether there are active tasks.  This avoids free-text parsing
and the unreliable HEARTBEAT_OK token.

Phase 2 (execution): only triggered when Phase 1 returns ``run``.  The
``on_execute`` callback runs the task through the full agent loop and
returns the result to deliver."""
    def __init__(self, workspace: Path, provider: LLMProvider, model: str, on_execute: Callable[[str], Coroutine[Any, Any, str]] | None = None, on_notify: Callable[[str], Coroutine[Any, Any, None]] | None = None, interval_s: int = 30 * 60, enabled: bool = True):
        ...
    @property
    def heartbeat_file(self) -> Path:
        ...
    def _read_heartbeat_file(self) -> str | None:
        ...
    async def _decide(self, content: str) -> tuple[str, str]:
        """Phase 1: ask LLM to decide skip/run via virtual tool call.

Returns (action, tasks) where action is 'skip' or 'run'."""
        ...
    async def start(self) -> None:
        """Start the heartbeat service."""
        ...
    def stop(self) -> None:
        """Stop the heartbeat service."""
        ...
    async def _run_loop(self) -> None:
        """Main heartbeat loop."""
        ...
    async def _tick(self) -> None:
        """Execute a single heartbeat tick."""
        ...
    async def trigger_now(self) -> str | None:
        """Manually trigger a heartbeat."""
        ...
