"""Mochat channel implementation using Socket.IO with HTTP polling fallback."""
from __future__ import annotations
import asyncio
import json
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any
import httpx
from loguru import logger
from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.base import BaseChannel
from nanobot.config.paths import get_runtime_subdir
from nanobot.config.schema import Base
from pydantic import Field
@dataclass
class MochatBufferedEntry:
    """Buffered inbound entry for delayed dispatch."""
    raw_body: str
    author: str
    sender_name: str = ''
    sender_username: str = ''
    timestamp: int | None = None
    message_id: str = ''
    group_id: str = ''
@dataclass
class DelayState:
    """Per-target delayed message state."""
    entries: list[MochatBufferedEntry] = field(default_factory=list)
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    timer: asyncio.Task | None = None
@dataclass
class MochatTarget:
    """Outbound target resolution result."""
    id: str
    is_panel: bool
def _safe_dict(value: Any) -> dict:
    """Return *value* if it's a dict, else empty dict."""
    ...
def _str_field(src: dict, *keys: str) -> str:
    """Return the first non-empty str value found for *keys*, stripped."""
    ...
def _make_synthetic_event(message_id: str, author: str, content: Any, meta: Any, group_id: str, converse_id: str = None, timestamp: Any = None, author_info: Any) -> dict[str, Any]:
    """Build a synthetic ``message.add`` event dict."""
    ...
def normalize_mochat_content(content: Any) -> str:
    """Normalize content payload to text."""
    ...
def resolve_mochat_target(raw: str) -> MochatTarget:
    """Resolve id and target kind from user-provided target string."""
    ...
def extract_mention_ids(value: Any) -> list[str]:
    """Extract mention ids from heterogeneous mention payload."""
    ...
def resolve_was_mentioned(payload: dict[str, Any], agent_user_id: str) -> bool:
    """Resolve mention state from payload metadata and text fallback."""
    ...
def resolve_require_mention(config: MochatConfig, session_id: str, group_id: str) -> bool:
    """Resolve mention requirement for group/panel conversations."""
    ...
def build_buffered_body(entries: list[MochatBufferedEntry], is_group: bool) -> str:
    """Build text body from one or more buffered entries."""
    ...
def parse_timestamp(value: Any) -> int | None:
    """Parse event timestamp to epoch milliseconds."""
    ...
class MochatMentionConfig(Base):
    """Mochat mention behavior configuration."""
    require_in_groups: bool = False
class MochatGroupRule(Base):
    """Mochat per-group mention requirement."""
    require_mention: bool = False
class MochatConfig(Base):
    """Mochat channel configuration."""
    enabled: bool = False
    base_url: str = 'https://mochat.io'
    socket_url: str = ''
    socket_path: str = '/socket.io'
    socket_disable_msgpack: bool = False
    socket_reconnect_delay_ms: int = 1000
    socket_max_reconnect_delay_ms: int = 10000
    socket_connect_timeout_ms: int = 10000
    refresh_interval_ms: int = 30000
    watch_timeout_ms: int = 25000
    watch_limit: int = 100
    retry_delay_ms: int = 500
    max_retry_attempts: int = 0
    claw_token: str = ''
    agent_user_id: str = ''
    sessions: list[str] = Field(default_factory=list)
    panels: list[str] = Field(default_factory=list)
    allow_from: list[str] = Field(default_factory=list)
    mention: MochatMentionConfig = Field(default_factory=MochatMentionConfig)
    groups: dict[str, MochatGroupRule] = Field(default_factory=dict)
    reply_delay_mode: str = 'non-mention'
    reply_delay_ms: int = 120000
class MochatChannel(BaseChannel):
    """Mochat channel using socket.io with fallback polling workers."""
    name = 'mochat'
    display_name = 'Mochat'
    @classmethod
    def default_config(cls) -> dict[str, Any]:
        ...
    def __init__(self, config: Any, bus: MessageBus):
        ...
    async def start(self) -> None:
        """Start Mochat channel workers and websocket connection."""
        ...
    async def stop(self) -> None:
        """Stop all workers and clean up resources."""
        ...
    async def send(self, msg: OutboundMessage) -> None:
        """Send outbound message to session or panel."""
        ...
    def _seed_targets_from_config(self) -> None:
        ...
    @staticmethod
    def _normalize_id_list(values: list[str]) -> tuple[list[str], bool]:
        ...
    async def _start_socket_client(self) -> bool:
        ...
    def _build_notify_handler(self, event_name: str):
        ...
    async def _subscribe_all(self) -> bool:
        ...
    async def _subscribe_sessions(self, session_ids: list[str]) -> bool:
        ...
    async def _subscribe_panels(self, panel_ids: list[str]) -> bool:
        ...
    async def _socket_call(self, event_name: str, payload: dict[str, Any]) -> dict[str, Any]:
        ...
    async def _refresh_loop(self) -> None:
        ...
    async def _refresh_targets(self, subscribe_new: bool) -> None:
        ...
    async def _refresh_sessions_directory(self, subscribe_new: bool) -> None:
        ...
    async def _refresh_panels(self, subscribe_new: bool) -> None:
        ...
    async def _ensure_fallback_workers(self) -> None:
        ...
    async def _stop_fallback_workers(self) -> None:
        ...
    async def _session_watch_worker(self, session_id: str) -> None:
        ...
    async def _panel_poll_worker(self, panel_id: str) -> None:
        ...
    async def _handle_watch_payload(self, payload: dict[str, Any], target_kind: str) -> None:
        ...
    async def _process_inbound_event(self, target_id: str, event: dict[str, Any], target_kind: str) -> None:
        ...
    def _remember_message_id(self, key: str, message_id: str) -> bool:
        ...
    async def _enqueue_delayed_entry(self, key: str, target_id: str, target_kind: str, entry: MochatBufferedEntry) -> None:
        ...
    async def _delay_flush_after(self, key: str, target_id: str, target_kind: str) -> None:
        ...
    async def _flush_delayed_entries(self, key: str, target_id: str, target_kind: str, reason: str, entry: MochatBufferedEntry | None) -> None:
        ...
    async def _dispatch_entries(self, target_id: str, target_kind: str, entries: list[MochatBufferedEntry], was_mentioned: bool) -> None:
        ...
    async def _cancel_delay_timers(self) -> None:
        ...
    async def _handle_notify_chat_message(self, payload: Any) -> None:
        ...
    async def _handle_notify_inbox_append(self, payload: Any) -> None:
        ...
    def _mark_session_cursor(self, session_id: str, cursor: int) -> None:
        ...
    async def _save_cursor_debounced(self) -> None:
        ...
    async def _load_session_cursors(self) -> None:
        ...
    async def _save_session_cursors(self) -> None:
        ...
    async def _post_json(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        ...
    async def _api_send(self, path: str, id_key: str, id_val: str, content: str, reply_to: str | None, group_id: str | None = None) -> dict[str, Any]:
        """Unified send helper for session and panel messages."""
        ...
    @staticmethod
    def _read_group_id(metadata: dict[str, Any]) -> str | None:
        ...
