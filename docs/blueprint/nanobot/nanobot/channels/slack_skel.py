"""Slack channel implementation using Socket Mode."""
import asyncio
import re
from typing import Any
from loguru import logger
from slack_sdk.socket_mode.request import SocketModeRequest
from slack_sdk.socket_mode.response import SocketModeResponse
from slack_sdk.socket_mode.websockets import SocketModeClient
from slack_sdk.web.async_client import AsyncWebClient
from slackify_markdown import slackify_markdown
from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from pydantic import Field
from nanobot.channels.base import BaseChannel
from nanobot.config.schema import Base
class SlackDMConfig(Base):
    """Slack DM policy configuration."""
    enabled: bool = True
    policy: str = 'open'
    allow_from: list[str] = Field(default_factory=list)
class SlackConfig(Base):
    """Slack channel configuration."""
    enabled: bool = False
    mode: str = 'socket'
    webhook_path: str = '/slack/events'
    bot_token: str = ''
    app_token: str = ''
    user_token_read_only: bool = True
    reply_in_thread: bool = True
    react_emoji: str = 'eyes'
    allow_from: list[str] = Field(default_factory=list)
    group_policy: str = 'mention'
    group_allow_from: list[str] = Field(default_factory=list)
    dm: SlackDMConfig = Field(default_factory=SlackDMConfig)
class SlackChannel(BaseChannel):
    """Slack channel using Socket Mode."""
    name = 'slack'
    display_name = 'Slack'
    @classmethod
    def default_config(cls) -> dict[str, Any]:
        ...
    def __init__(self, config: Any, bus: MessageBus):
        ...
    async def start(self) -> None:
        """Start the Slack Socket Mode client."""
        ...
    async def stop(self) -> None:
        """Stop the Slack client."""
        ...
    async def send(self, msg: OutboundMessage) -> None:
        """Send a message through Slack."""
        ...
    async def _on_socket_request(self, client: SocketModeClient, req: SocketModeRequest) -> None:
        """Handle incoming Socket Mode requests."""
        ...
    def _is_allowed(self, sender_id: str, chat_id: str, channel_type: str) -> bool:
        ...
    def _should_respond_in_channel(self, event_type: str, text: str, chat_id: str) -> bool:
        ...
    def _strip_bot_mention(self, text: str) -> str:
        ...
    _TABLE_RE = re.compile('(?m)^\\|.*\\|$(?:\\n\\|[\\s:|-]*\\|$)(?:\\n\\|.*\\|$)*')
    _CODE_FENCE_RE = re.compile('```[\\s\\S]*?```')
    _INLINE_CODE_RE = re.compile('`[^`]+`')
    _LEFTOVER_BOLD_RE = re.compile('\\*\\*(.+?)\\*\\*')
    _LEFTOVER_HEADER_RE = re.compile('^#{1,6}\\s+(.+)$', re.MULTILINE)
    _BARE_URL_RE = re.compile('(?<![|<])(https?://\\S+)')
    @classmethod
    def _to_mrkdwn(cls, text: str) -> str:
        """Convert Markdown to Slack mrkdwn, including tables."""
        ...
    @classmethod
    def _fixup_mrkdwn(cls, text: str) -> str:
        """Fix markdown artifacts that slackify_markdown misses."""
        ...
    @staticmethod
    def _convert_table(match: re.Match) -> str:
        """Convert a Markdown table to a Slack-readable list."""
        ...
