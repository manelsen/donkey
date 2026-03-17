"""Runtime path helpers derived from the active config context."""
from __future__ import annotations
from pathlib import Path
from nanobot.config.loader import get_config_path
from nanobot.utils.helpers import ensure_dir
def get_data_dir() -> Path:
    """Return the instance-level runtime data directory."""
    ...
def get_runtime_subdir(name: str) -> Path:
    """Return a named runtime subdirectory under the instance data dir."""
    ...
def get_media_dir(channel: str | None = None) -> Path:
    """Return the media directory, optionally namespaced per channel."""
    ...
def get_cron_dir() -> Path:
    """Return the cron storage directory."""
    ...
def get_logs_dir() -> Path:
    """Return the logs directory."""
    ...
def get_workspace_path(workspace: str | None = None) -> Path:
    """Resolve and ensure the agent workspace path."""
    ...
def get_cli_history_path() -> Path:
    """Return the shared CLI history file path."""
    ...
def get_bridge_install_dir() -> Path:
    """Return the shared WhatsApp bridge installation directory."""
    ...
def get_legacy_sessions_dir() -> Path:
    """Return the legacy global session directory used for migration fallback."""
    ...
