"""DingTalk/DingDing channel implementation using Stream Mode."""
import asyncio
import json
import mimetypes
import os
import time
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse
import httpx
from loguru import logger
from pydantic import Field
from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.base import BaseChannel
from nanobot.config.schema import Base
class NanobotDingTalkHandler(CallbackHandler):
    """Standard DingTalk Stream SDK Callback Handler.
Parses incoming messages and forwards them to the Nanobot channel."""
    def __init__(self, channel: 'DingTalkChannel'):
        ...
    async def process(self, message: CallbackMessage):
        """Process incoming stream message."""
        ...
class DingTalkConfig(Base):
    """DingTalk channel configuration using Stream mode."""
    enabled: bool = False
    client_id: str = ''
    client_secret: str = ''
    allow_from: list[str] = Field(default_factory=list)
class DingTalkChannel(BaseChannel):
    """DingTalk channel using Stream Mode.

Uses WebSocket to receive events via `dingtalk-stream` SDK.
Uses direct HTTP API to send messages (SDK is mainly for receiving).

Supports both private (1:1) and group chats.
Group chat_id is stored with a "group:" prefix to route replies back."""
    name = 'dingtalk'
    display_name = 'DingTalk'
    _IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'}
    _AUDIO_EXTS = {'.amr', '.mp3', '.wav', '.ogg', '.m4a', '.aac'}
    _VIDEO_EXTS = {'.mp4', '.mov', '.avi', '.mkv', '.webm'}
    @classmethod
    def default_config(cls) -> dict[str, Any]:
        ...
    def __init__(self, config: Any, bus: MessageBus):
        ...
    async def start(self) -> None:
        """Start the DingTalk bot with Stream Mode."""
        ...
    async def stop(self) -> None:
        """Stop the DingTalk bot."""
        ...
    async def _get_access_token(self) -> str | None:
        """Get or refresh Access Token."""
        ...
    @staticmethod
    def _is_http_url(value: str) -> bool:
        ...
    def _guess_upload_type(self, media_ref: str) -> str:
        ...
    def _guess_filename(self, media_ref: str, upload_type: str) -> str:
        ...
    async def _read_media_bytes(self, media_ref: str) -> tuple[bytes | None, str | None, str | None]:
        ...
    async def _upload_media(self, token: str, data: bytes, media_type: str, filename: str, content_type: str | None) -> str | None:
        ...
    async def _send_batch_message(self, token: str, chat_id: str, msg_key: str, msg_param: dict[str, Any]) -> bool:
        ...
    async def _send_markdown_text(self, token: str, chat_id: str, content: str) -> bool:
        ...
    async def _send_media_ref(self, token: str, chat_id: str, media_ref: str) -> bool:
        ...
    async def send(self, msg: OutboundMessage) -> None:
        """Send a message through DingTalk."""
        ...
    async def _on_message(self, content: str, sender_id: str, sender_name: str, conversation_type: str | None = None, conversation_id: str | None = None) -> None:
        """Handle incoming message (called by NanobotDingTalkHandler).

Delegates to BaseChannel._handle_message() which enforces allow_from
permission checks before publishing to the bus."""
        ...
    async def _download_dingtalk_file(self, download_code: str, filename: str, sender_id: str) -> str | None:
        """Download a DingTalk file to the media directory, return local path."""
        ...
