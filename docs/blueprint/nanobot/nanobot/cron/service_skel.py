"""Cron service for scheduling agent tasks."""
import asyncio
import json
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Coroutine
from loguru import logger
from nanobot.cron.types import CronJob, CronJobState, CronPayload, CronSchedule, CronStore
def _now_ms() -> int:
    ...
def _compute_next_run(schedule: CronSchedule, now_ms: int) -> int | None:
    """Compute next run time in ms."""
    ...
def _validate_schedule_for_add(schedule: CronSchedule) -> None:
    """Validate schedule fields that would otherwise create non-runnable jobs."""
    ...
class CronService:
    """Service for managing and executing scheduled jobs."""
    def __init__(self, store_path: Path, on_job: Callable[[CronJob], Coroutine[Any, Any, str | None]] | None = None):
        ...
    def _load_store(self) -> CronStore:
        """Load jobs from disk. Reloads automatically if file was modified externally."""
        ...
    def _save_store(self) -> None:
        """Save jobs to disk."""
        ...
    async def start(self) -> None:
        """Start the cron service."""
        ...
    def stop(self) -> None:
        """Stop the cron service."""
        ...
    def _recompute_next_runs(self) -> None:
        """Recompute next run times for all enabled jobs."""
        ...
    def _get_next_wake_ms(self) -> int | None:
        """Get the earliest next run time across all jobs."""
        ...
    def _arm_timer(self) -> None:
        """Schedule the next timer tick."""
        ...
    async def _on_timer(self) -> None:
        """Handle timer tick - run due jobs."""
        ...
    async def _execute_job(self, job: CronJob) -> None:
        """Execute a single job."""
        ...
    def list_jobs(self, include_disabled: bool = False) -> list[CronJob]:
        """List all jobs."""
        ...
    def add_job(self, name: str, schedule: CronSchedule, message: str, deliver: bool = False, channel: str | None = None, to: str | None = None, delete_after_run: bool = False) -> CronJob:
        """Add a new job."""
        ...
    def remove_job(self, job_id: str) -> bool:
        """Remove a job by ID."""
        ...
    def enable_job(self, job_id: str, enabled: bool = True) -> CronJob | None:
        """Enable or disable a job."""
        ...
    async def run_job(self, job_id: str, force: bool = False) -> bool:
        """Manually run a job."""
        ...
    def status(self) -> dict:
        """Get service status."""
        ...
