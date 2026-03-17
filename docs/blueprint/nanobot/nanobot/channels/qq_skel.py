"""QQ channel implementation using botpy SDK."""
import asyncio
from collections import deque
from typing import TYPE_CHECKING, Any, Literal
from loguru import logger
from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.base import BaseChannel
from nanobot.config.schema import Base
from pydantic import Field
def _make_bot_class(channel: 'QQChannel') -> 'type[botpy.Client]':
    """Create a botpy Client subclass bound to the given channel."""
    ...
class QQConfig(Base):
    """QQ channel configuration using botpy SDK."""
    enabled: bool = False
    app_id: str = ''
    secret: str = ''
    allow_from: list[str] = Field(default_factory=list)
    msg_format: Literal['plain', 'markdown'] = 'plain'
class QQChannel(BaseChannel):
    """QQ channel using botpy SDK with WebSocket connection."""
    name = 'qq'
    display_name = 'QQ'
    @classmethod
    def default_config(cls) -> dict[str, Any]:
        ...
    def __init__(self, config: Any, bus: MessageBus):
        ...
    async def start(self) -> None:
        """Start the QQ bot."""
        ...
    async def _run_bot(self) -> None:
        """Run the bot connection with auto-reconnect."""
        ...
    async def stop(self) -> None:
        """Stop the QQ bot."""
        ...
    async def send(self, msg: OutboundMessage) -> None:
        """Send a message through QQ."""
        ...
    async def _on_message(self, data: 'C2CMessage | GroupMessage', is_group: bool = False) -> None:
        """Handle incoming message from QQ."""
        ...
