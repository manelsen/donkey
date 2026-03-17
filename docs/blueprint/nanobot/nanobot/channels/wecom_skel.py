"""WeCom (Enterprise WeChat) channel implementation using wecom_aibot_sdk."""
import asyncio
import importlib.util
import os
from collections import OrderedDict
from typing import Any
from loguru import logger
from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.base import BaseChannel
from nanobot.config.paths import get_media_dir
from nanobot.config.schema import Base
from pydantic import Field
class WecomConfig(Base):
    """WeCom (Enterprise WeChat) AI Bot channel configuration."""
    enabled: bool = False
    bot_id: str = ''
    secret: str = ''
    allow_from: list[str] = Field(default_factory=list)
    welcome_message: str = ''
class WecomChannel(BaseChannel):
    """WeCom (Enterprise WeChat) channel using WebSocket long connection.

Uses WebSocket to receive events - no public IP or webhook required.

Requires:
- Bot ID and Secret from WeCom AI Bot platform"""
    name = 'wecom'
    display_name = 'WeCom'
    @classmethod
    def default_config(cls) -> dict[str, Any]:
        ...
    def __init__(self, config: Any, bus: MessageBus):
        ...
    async def start(self) -> None:
        """Start the WeCom bot with WebSocket long connection."""
        ...
    async def stop(self) -> None:
        """Stop the WeCom bot."""
        ...
    async def _on_connected(self, frame: Any) -> None:
        """Handle WebSocket connected event."""
        ...
    async def _on_authenticated(self, frame: Any) -> None:
        """Handle authentication success event."""
        ...
    async def _on_disconnected(self, frame: Any) -> None:
        """Handle WebSocket disconnected event."""
        ...
    async def _on_error(self, frame: Any) -> None:
        """Handle error event."""
        ...
    async def _on_text_message(self, frame: Any) -> None:
        """Handle text message."""
        ...
    async def _on_image_message(self, frame: Any) -> None:
        """Handle image message."""
        ...
    async def _on_voice_message(self, frame: Any) -> None:
        """Handle voice message."""
        ...
    async def _on_file_message(self, frame: Any) -> None:
        """Handle file message."""
        ...
    async def _on_mixed_message(self, frame: Any) -> None:
        """Handle mixed content message."""
        ...
    async def _on_enter_chat(self, frame: Any) -> None:
        """Handle enter_chat event (user opens chat with bot)."""
        ...
    async def _process_message(self, frame: Any, msg_type: str) -> None:
        """Process incoming message and forward to bus."""
        ...
    async def _download_and_save_media(self, file_url: str, aes_key: str, media_type: str, filename: str | None = None) -> str | None:
        """Download and decrypt media from WeCom.

Returns:
    file_path or None if download failed"""
        ...
    async def send(self, msg: OutboundMessage) -> None:
        """Send a message through WeCom."""
        ...
