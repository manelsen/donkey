"""Discord channel implementation using Discord Gateway websocket."""
import asyncio
import json
from pathlib import Path
from typing import Any, Literal
import httpx
from pydantic import Field
import websockets
from loguru import logger
from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.base import BaseChannel
from nanobot.config.paths import get_media_dir
from nanobot.config.schema import Base
from nanobot.utils.helpers import split_message
class DiscordConfig(Base):
    """Discord channel configuration."""
    enabled: bool = False
    token: str = ''
    allow_from: list[str] = Field(default_factory=list)
    gateway_url: str = 'wss://gateway.discord.gg/?v=10&encoding=json'
    intents: int = 37377
    group_policy: Literal['mention', 'open'] = 'mention'
class DiscordChannel(BaseChannel):
    """Discord channel using Gateway websocket."""
    name = 'discord'
    display_name = 'Discord'
    @classmethod
    def default_config(cls) -> dict[str, Any]:
        ...
    def __init__(self, config: Any, bus: MessageBus):
        ...
    async def start(self) -> None:
        """Start the Discord gateway connection."""
        ...
    async def stop(self) -> None:
        """Stop the Discord channel."""
        ...
    async def send(self, msg: OutboundMessage) -> None:
        """Send a message through Discord REST API, including file attachments."""
        ...
    async def _send_payload(self, url: str, headers: dict[str, str], payload: dict[str, Any]) -> bool:
        """Send a single Discord API payload with retry on rate-limit. Returns True on success."""
        ...
    async def _send_file(self, url: str, headers: dict[str, str], file_path: str, reply_to: str | None = None) -> bool:
        """Send a file attachment via Discord REST API using multipart/form-data."""
        ...
    async def _gateway_loop(self) -> None:
        """Main gateway loop: identify, heartbeat, dispatch events."""
        ...
    async def _identify(self) -> None:
        """Send IDENTIFY payload."""
        ...
    async def _start_heartbeat(self, interval_s: float) -> None:
        """Start or restart the heartbeat loop."""
        ...
    async def _handle_message_create(self, payload: dict[str, Any]) -> None:
        """Handle incoming Discord messages."""
        ...
    def _should_respond_in_group(self, payload: dict[str, Any], content: str) -> bool:
        """Check if bot should respond in a group channel based on policy."""
        ...
    async def _start_typing(self, channel_id: str) -> None:
        """Start periodic typing indicator for a channel."""
        ...
    async def _stop_typing(self, channel_id: str) -> None:
        """Stop typing indicator for a channel."""
        ...
