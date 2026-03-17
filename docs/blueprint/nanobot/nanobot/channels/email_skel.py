"""Email channel implementation using IMAP polling + SMTP replies."""
import asyncio
import html
import imaplib
import re
import smtplib
import ssl
from datetime import date
from email import policy
from email.header import decode_header, make_header
from email.message import EmailMessage
from email.parser import BytesParser
from email.utils import parseaddr
from typing import Any
from loguru import logger
from pydantic import Field
from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.base import BaseChannel
from nanobot.config.schema import Base
class EmailConfig(Base):
    """Email channel configuration (IMAP inbound + SMTP outbound)."""
    enabled: bool = False
    consent_granted: bool = False
    imap_host: str = ''
    imap_port: int = 993
    imap_username: str = ''
    imap_password: str = ''
    imap_mailbox: str = 'INBOX'
    imap_use_ssl: bool = True
    smtp_host: str = ''
    smtp_port: int = 587
    smtp_username: str = ''
    smtp_password: str = ''
    smtp_use_tls: bool = True
    smtp_use_ssl: bool = False
    from_address: str = ''
    auto_reply_enabled: bool = True
    poll_interval_seconds: int = 30
    mark_seen: bool = True
    max_body_chars: int = 12000
    subject_prefix: str = 'Re: '
    allow_from: list[str] = Field(default_factory=list)
class EmailChannel(BaseChannel):
    """Email channel.

Inbound:
- Poll IMAP mailbox for unread messages.
- Convert each message into an inbound event.

Outbound:
- Send responses via SMTP back to the sender address."""
    name = 'email'
    display_name = 'Email'
    _IMAP_MONTHS = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec')
    @classmethod
    def default_config(cls) -> dict[str, Any]:
        ...
    def __init__(self, config: Any, bus: MessageBus):
        ...
    async def start(self) -> None:
        """Start polling IMAP for inbound emails."""
        ...
    async def stop(self) -> None:
        """Stop polling loop."""
        ...
    async def send(self, msg: OutboundMessage) -> None:
        """Send email via SMTP."""
        ...
    def _validate_config(self) -> bool:
        ...
    def _smtp_send(self, msg: EmailMessage) -> None:
        ...
    def _fetch_new_messages(self) -> list[dict[str, Any]]:
        """Poll IMAP and return parsed unread messages."""
        ...
    def fetch_messages_between_dates(self, start_date: date, end_date: date, limit: int = 20) -> list[dict[str, Any]]:
        """Fetch messages in [start_date, end_date) by IMAP date search.

This is used for historical summarization tasks (e.g. "yesterday")."""
        ...
    def _fetch_messages(self, search_criteria: tuple[str, ...], mark_seen: bool, dedupe: bool, limit: int) -> list[dict[str, Any]]:
        """Fetch messages by arbitrary IMAP search criteria."""
        ...
    @classmethod
    def _format_imap_date(cls, value: date) -> str:
        """Format date for IMAP search (always English month abbreviations)."""
        ...
    @staticmethod
    def _extract_message_bytes(fetched: list[Any]) -> bytes | None:
        ...
    @staticmethod
    def _extract_uid(fetched: list[Any]) -> str:
        ...
    @staticmethod
    def _decode_header_value(value: str) -> str:
        ...
    @classmethod
    def _extract_text_body(cls, msg: Any) -> str:
        """Best-effort extraction of readable body text."""
        ...
    @staticmethod
    def _html_to_text(raw_html: str) -> str:
        ...
    def _reply_subject(self, base_subject: str) -> str:
        ...
