"""Feishu/Lark channel implementation using lark-oapi SDK with WebSocket long connection."""
import asyncio
import json
import os
import re
import threading
from collections import OrderedDict
from pathlib import Path
from typing import Any, Literal
from loguru import logger
from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.base import BaseChannel
from nanobot.config.paths import get_media_dir
from nanobot.config.schema import Base
from pydantic import Field
import importlib.util
def _extract_share_card_content(content_json: dict, msg_type: str) -> str:
    """Extract text representation from share cards and interactive messages."""
    ...
def _extract_interactive_content(content: dict) -> list[str]:
    """Recursively extract text and links from interactive card content."""
    ...
def _extract_element_content(element: dict) -> list[str]:
    """Extract content from a single card element."""
    ...
def _extract_post_content(content_json: dict) -> tuple[str, list[str]]:
    """Extract text and image keys from Feishu post (rich text) message.

Handles three payload shapes:
- Direct:    {"title": "...", "content": [[...]]}
- Localized: {"zh_cn": {"title": "...", "content": [...]}}
- Wrapped:   {"post": {"zh_cn": {"title": "...", "content": [...]}}}"""
    ...
def _extract_post_text(content_json: dict) -> str:
    """Extract plain text from Feishu post (rich text) message content.

Legacy wrapper for _extract_post_content, returns only text."""
    ...
class FeishuConfig(Base):
    """Feishu/Lark channel configuration using WebSocket long connection."""
    enabled: bool = False
    app_id: str = ''
    app_secret: str = ''
    encrypt_key: str = ''
    verification_token: str = ''
    allow_from: list[str] = Field(default_factory=list)
    react_emoji: str = 'THUMBSUP'
    group_policy: Literal['open', 'mention'] = 'mention'
    reply_to_message: bool = False
class FeishuChannel(BaseChannel):
    """Feishu/Lark channel using WebSocket long connection.

Uses WebSocket to receive events - no public IP or webhook required.

Requires:
- App ID and App Secret from Feishu Open Platform
- Bot capability enabled
- Event subscription enabled (im.message.receive_v1)"""
    name = 'feishu'
    display_name = 'Feishu'
    @classmethod
    def default_config(cls) -> dict[str, Any]:
        ...
    def __init__(self, config: Any, bus: MessageBus):
        ...
    @staticmethod
    def _register_optional_event(builder: Any, method_name: str, handler: Any) -> Any:
        """Register an event handler only when the SDK supports it."""
        ...
    async def start(self) -> None:
        """Start the Feishu bot with WebSocket long connection."""
        ...
    async def stop(self) -> None:
        """Stop the Feishu bot.

Notice: lark.ws.Client does not expose stop method， simply exiting the program will close the client.

Reference: https://github.com/larksuite/oapi-sdk-python/blob/v2_main/lark_oapi/ws/client.py#L86"""
        ...
    def _is_bot_mentioned(self, message: Any) -> bool:
        """Check if the bot is @mentioned in the message."""
        ...
    def _is_group_message_for_bot(self, message: Any) -> bool:
        """Allow group messages when policy is open or bot is @mentioned."""
        ...
    def _add_reaction_sync(self, message_id: str, emoji_type: str) -> None:
        """Sync helper for adding reaction (runs in thread pool)."""
        ...
    async def _add_reaction(self, message_id: str, emoji_type: str = 'THUMBSUP') -> None:
        """Add a reaction emoji to a message (non-blocking).

Common emoji types: THUMBSUP, OK, EYES, DONE, OnIt, HEART"""
        ...
    _TABLE_RE = re.compile('((?:^[ \\t]*\\|.+\\|[ \\t]*\\n)(?:^[ \\t]*\\|[-:\\s|]+\\|[ \\t]*\\n)(?:^[ \\t]*\\|.+\\|[ \\t]*\\n?)+)', re.MULTILINE)
    _HEADING_RE = re.compile('^(#{1,6})\\s+(.+)$', re.MULTILINE)
    _CODE_BLOCK_RE = re.compile('(```[\\s\\S]*?```)', re.MULTILINE)
    @staticmethod
    def _parse_md_table(table_text: str) -> dict | None:
        """Parse a markdown table into a Feishu table element."""
        ...
    def _build_card_elements(self, content: str) -> list[dict]:
        """Split content into div/markdown + table elements for Feishu card."""
        ...
    @staticmethod
    def _split_elements_by_table_limit(elements: list[dict], max_tables: int = 1) -> list[list[dict]]:
        """Split card elements into groups with at most *max_tables* table elements each.

Feishu cards have a hard limit of one table per card (API error 11310).
When the rendered content contains multiple markdown tables each table is
placed in a separate card message so every table reaches the user."""
        ...
    def _split_headings(self, content: str) -> list[dict]:
        """Split content by headings, converting headings to div elements."""
        ...
    _COMPLEX_MD_RE = re.compile('```|^\\|.+\\|.*\\n\\s*\\|[-:\\s|]+\\||^#{1,6}\\s+', re.MULTILINE)
    _SIMPLE_MD_RE = re.compile('\\*\\*.+?\\*\\*|__.+?__|(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|~~.+?~~', re.DOTALL)
    _MD_LINK_RE = re.compile('\\[([^\\]]+)\\]\\((https?://[^\\)]+)\\)')
    _LIST_RE = re.compile('^[\\s]*[-*+]\\s+', re.MULTILINE)
    _OLIST_RE = re.compile('^[\\s]*\\d+\\.\\s+', re.MULTILINE)
    _TEXT_MAX_LEN = 200
    _POST_MAX_LEN = 2000
    @classmethod
    def _detect_msg_format(cls, content: str) -> str:
        """Determine the optimal Feishu message format for *content*.

Returns one of:
- ``"text"``        – plain text, short and no markdown
- ``"post"``        – rich text (links only, moderate length)
- ``"interactive"`` – card with full markdown rendering"""
        ...
    @classmethod
    def _markdown_to_post(cls, content: str) -> str:
        """Convert markdown content to Feishu post message JSON.

Handles links ``[text](url)`` as ``a`` tags; everything else as ``text`` tags.
Each line becomes a paragraph (row) in the post body."""
        ...
    _IMAGE_EXTS = {'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.ico', '.tiff', '.tif'}
    _AUDIO_EXTS = {'.opus'}
    _VIDEO_EXTS = {'.mp4', '.mov', '.avi'}
    _FILE_TYPE_MAP = {'.opus': 'opus', '.mp4': 'mp4', '.pdf': 'pdf', '.doc': 'doc', '.docx': 'doc', '.xls': 'xls', '.xlsx': 'xls', '.ppt': 'ppt', '.pptx': 'ppt'}
    def _upload_image_sync(self, file_path: str) -> str | None:
        """Upload an image to Feishu and return the image_key."""
        ...
    def _upload_file_sync(self, file_path: str) -> str | None:
        """Upload a file to Feishu and return the file_key."""
        ...
    def _download_image_sync(self, message_id: str, image_key: str) -> tuple[bytes | None, str | None]:
        """Download an image from Feishu message by message_id and image_key."""
        ...
    def _download_file_sync(self, message_id: str, file_key: str, resource_type: str = 'file') -> tuple[bytes | None, str | None]:
        """Download a file/audio/media from a Feishu message by message_id and file_key."""
        ...
    async def _download_and_save_media(self, msg_type: str, content_json: dict, message_id: str | None = None) -> tuple[str | None, str]:
        """Download media from Feishu and save to local disk.

Returns:
    (file_path, content_text) - file_path is None if download failed"""
        ...
    _REPLY_CONTEXT_MAX_LEN = 200
    def _get_message_content_sync(self, message_id: str) -> str | None:
        """Fetch the text content of a Feishu message by ID (synchronous).

Returns a "[Reply to: ...]" context string, or None on failure."""
        ...
    def _reply_message_sync(self, parent_message_id: str, msg_type: str, content: str) -> bool:
        """Reply to an existing Feishu message using the Reply API (synchronous)."""
        ...
    def _send_message_sync(self, receive_id_type: str, receive_id: str, msg_type: str, content: str) -> bool:
        """Send a single message (text/image/file/interactive) synchronously."""
        ...
    async def send(self, msg: OutboundMessage) -> None:
        """Send a message through Feishu, including media (images/files) if present."""
        ...
    def _on_message_sync(self, data: Any) -> None:
        """Sync handler for incoming messages (called from WebSocket thread).
Schedules async handling in the main event loop."""
        ...
    async def _on_message(self, data: Any) -> None:
        """Handle incoming message from Feishu."""
        ...
    def _on_reaction_created(self, data: Any) -> None:
        """Ignore reaction events so they do not generate SDK noise."""
        ...
    def _on_message_read(self, data: Any) -> None:
        """Ignore read events so they do not generate SDK noise."""
        ...
    def _on_bot_p2p_chat_entered(self, data: Any) -> None:
        """Ignore p2p-enter events when a user opens a bot chat."""
        ...
    @staticmethod
    def _format_tool_hint_lines(tool_hint: str) -> str:
        """Split tool hints across lines on top-level call separators only."""
        ...
    async def _send_tool_hint_card(self, receive_id_type: str, receive_id: str, tool_hint: str) -> None:
        """Send tool hint as an interactive card with formatted code block.

Args:
    receive_id_type: "chat_id" or "open_id"
    receive_id: The target chat or user ID
    tool_hint: Formatted tool hint string (e.g., 'web_search("q"), read_file("path")')"""
        ...
