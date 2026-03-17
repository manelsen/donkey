"""WhatsApp channel implementation using Node.js bridge."""
import asyncio
import json
import mimetypes
from collections import OrderedDict
from typing import Any
from loguru import logger
from pydantic import Field
from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.base import BaseChannel
from nanobot.config.schema import Base
class WhatsAppConfig(Base):
    """WhatsApp channel configuration."""
    enabled: bool = False
    bridge_url: str = 'ws://localhost:3001'
    bridge_token: str = ''
    allow_from: list[str] = Field(default_factory=list)
class WhatsAppChannel(BaseChannel):
    """WhatsApp channel that connects to a Node.js bridge.

The bridge uses @whiskeysockets/baileys to handle the WhatsApp Web protocol.
Communication between Python and Node.js is via WebSocket."""
    name = 'whatsapp'
    display_name = 'WhatsApp'
    @classmethod
    def default_config(cls) -> dict[str, Any]:
        ...
    def __init__(self, config: Any, bus: MessageBus):
        ...
    async def start(self) -> None:
        """Start the WhatsApp channel by connecting to the bridge."""
        ...
    async def stop(self) -> None:
        """Stop the WhatsApp channel."""
        ...
    async def send(self, msg: OutboundMessage) -> None:
        """Send a message through WhatsApp."""
        ...
    async def _handle_bridge_message(self, raw: str) -> None:
        """Handle a message from the bridge."""
        ...
