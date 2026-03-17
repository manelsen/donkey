"""Network security utilities — SSRF protection and internal URL detection."""
from __future__ import annotations
import ipaddress
import re
import socket
from urllib.parse import urlparse
def _is_private(addr: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    ...
def validate_url_target(url: str) -> tuple[bool, str]:
    """Validate a URL is safe to fetch: scheme, hostname, and resolved IPs.

Returns (ok, error_message).  When ok is True, error_message is empty."""
    ...
def validate_resolved_url(url: str) -> tuple[bool, str]:
    """Validate an already-fetched URL (e.g. after redirect). Only checks the IP, skips DNS."""
    ...
def contains_internal_url(command: str) -> bool:
    """Return True if the command string contains a URL targeting an internal/private address."""
    ...
