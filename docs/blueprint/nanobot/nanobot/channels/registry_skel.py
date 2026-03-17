"""Auto-discovery for built-in channel modules and external plugins."""
from __future__ import annotations
import importlib
import pkgutil
from typing import TYPE_CHECKING
from loguru import logger
def discover_channel_names() -> list[str]:
    """Return all built-in channel module names by scanning the package (zero imports)."""
    ...
def load_channel_class(module_name: str) -> type[BaseChannel]:
    """Import *module_name* and return the first BaseChannel subclass found."""
    ...
def discover_plugins() -> dict[str, type[BaseChannel]]:
    """Discover external channel plugins registered via entry_points."""
    ...
def discover_all() -> dict[str, type[BaseChannel]]:
    """Return all channels: built-in (pkgutil) merged with external (entry_points).

Built-in channels take priority — an external plugin cannot shadow a built-in name."""
    ...
