"""Web tools: web_search and web_fetch."""
from __future__ import annotations
import asyncio
import html
import json
import os
import re
from typing import TYPE_CHECKING, Any
from urllib.parse import urlparse
import httpx
from loguru import logger
from nanobot.agent.tools.base import Tool
def _strip_tags(text: str) -> str:
    """Remove HTML tags and decode entities."""
    ...
def _normalize(text: str) -> str:
    """Normalize whitespace."""
    ...
def _validate_url(url: str) -> tuple[bool, str]:
    """Validate URL scheme/domain. Does NOT check resolved IPs (use _validate_url_safe for that)."""
    ...
def _validate_url_safe(url: str) -> tuple[bool, str]:
    """Validate URL with SSRF protection: scheme, domain, and resolved IP check."""
    ...
def _format_results(query: str, items: list[dict[str, Any]], n: int) -> str:
    """Format provider results into shared plaintext output."""
    ...
class WebSearchTool(Tool):
    """Search the web using configured provider."""
    name = 'web_search'
    description = 'Search the web. Returns titles, URLs, and snippets.'
    parameters = {'type': 'object', 'properties': {'query': {'type': 'string', 'description': 'Search query'}, 'count': {'type': 'integer', 'description': 'Results (1-10)', 'minimum': 1, 'maximum': 10}}, 'required': ['query']}
    def __init__(self, config: WebSearchConfig | None = None, proxy: str | None = None):
        ...
    async def execute(self, query: str, count: int | None = None, **kwargs: Any) -> str:
        ...
    async def _search_brave(self, query: str, n: int) -> str:
        ...
    async def _search_tavily(self, query: str, n: int) -> str:
        ...
    async def _search_searxng(self, query: str, n: int) -> str:
        ...
    async def _search_jina(self, query: str, n: int) -> str:
        ...
    async def _search_duckduckgo(self, query: str, n: int) -> str:
        ...
class WebFetchTool(Tool):
    """Fetch and extract content from a URL."""
    name = 'web_fetch'
    description = 'Fetch URL and extract readable content (HTML → markdown/text).'
    parameters = {'type': 'object', 'properties': {'url': {'type': 'string', 'description': 'URL to fetch'}, 'extractMode': {'type': 'string', 'enum': ['markdown', 'text'], 'default': 'markdown'}, 'maxChars': {'type': 'integer', 'minimum': 100}}, 'required': ['url']}
    def __init__(self, max_chars: int = 50000, proxy: str | None = None):
        ...
    async def execute(self, url: str, extractMode: str = 'markdown', maxChars: int | None = None, **kwargs: Any) -> str:
        ...
    async def _fetch_jina(self, url: str, max_chars: int) -> str | None:
        """Try fetching via Jina Reader API. Returns None on failure."""
        ...
    async def _fetch_readability(self, url: str, extract_mode: str, max_chars: int) -> str:
        """Local fallback using readability-lxml."""
        ...
    def _to_markdown(self, html_content: str) -> str:
        """Convert HTML to markdown."""
        ...
