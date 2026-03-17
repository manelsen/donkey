"""Post-run evaluation for background tasks (heartbeat & cron).

After the agent executes a background task, this module makes a lightweight
LLM call to decide whether the result warrants notifying the user."""
from __future__ import annotations
from typing import TYPE_CHECKING
from loguru import logger
async def evaluate_response(response: str, task_context: str, provider: LLMProvider, model: str) -> bool:
    """Decide whether a background-task result should be delivered to the user.

Uses a lightweight tool-call LLM request (same pattern as heartbeat
``_decide()``).  Falls back to ``True`` (notify) on any failure so
that important messages are never silently dropped."""
    ...
