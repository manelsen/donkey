"""Message tool for sending messages to users."""
from typing import Any, Awaitable, Callable
from nanobot.agent.tools.base import Tool
from nanobot.bus.events import OutboundMessage
class MessageTool(Tool):
    """Tool to send messages to users on chat channels."""
    def __init__(self, send_callback: Callable[[OutboundMessage], Awaitable[None]] | None = None, default_channel: str = '', default_chat_id: str = '', default_message_id: str | None = None):
        ...
    def set_context(self, channel: str, chat_id: str, message_id: str | None = None) -> None:
        """Set the current message context."""
        ...
    def set_send_callback(self, callback: Callable[[OutboundMessage], Awaitable[None]]) -> None:
        """Set the callback for sending messages."""
        ...
    def start_turn(self) -> None:
        """Reset per-turn send tracking."""
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def description(self) -> str:
        ...
    @property
    def parameters(self) -> dict[str, Any]:
        ...
    async def execute(self, content: str, channel: str | None = None, chat_id: str | None = None, message_id: str | None = None, media: list[str] | None = None, **kwargs: Any) -> str:
        ...
