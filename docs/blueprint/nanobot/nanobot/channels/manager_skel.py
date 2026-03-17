"""Channel manager for coordinating chat channels."""
from __future__ import annotations
import asyncio
from typing import Any
from loguru import logger
from nanobot.bus.queue import MessageBus
from nanobot.channels.base import BaseChannel
from nanobot.config.schema import Config
class ChannelManager:
    """Manages chat channels and coordinates message routing.

Responsibilities:
- Initialize enabled channels (Telegram, WhatsApp, etc.)
- Start/stop channels
- Route outbound messages"""
    def __init__(self, config: Config, bus: MessageBus):
        ...
    def _init_channels(self) -> None:
        """Initialize channels discovered via pkgutil scan + entry_points plugins."""
        ...
    def _validate_allow_from(self) -> None:
        ...
    async def _start_channel(self, name: str, channel: BaseChannel) -> None:
        """Start a channel and log any exceptions."""
        ...
    async def start_all(self) -> None:
        """Start all channels and the outbound dispatcher."""
        ...
    async def stop_all(self) -> None:
        """Stop all channels and the dispatcher."""
        ...
    async def _dispatch_outbound(self) -> None:
        """Dispatch outbound messages to the appropriate channel."""
        ...
    def get_channel(self, name: str) -> BaseChannel | None:
        """Get a channel by name."""
        ...
    def get_status(self) -> dict[str, Any]:
        """Get status of all channels."""
        ...
    @property
    def enabled_channels(self) -> list[str]:
        """Get list of enabled channel names."""
        ...
