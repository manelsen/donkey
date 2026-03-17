"""Configuration loading utilities."""
import json
from pathlib import Path
from nanobot.config.schema import Config
def set_config_path(path: Path) -> None:
    """Set the current config path (used to derive data directory)."""
    ...
def get_config_path() -> Path:
    """Get the configuration file path."""
    ...
def load_config(config_path: Path | None = None) -> Config:
    """Load configuration from file or create default.

Args:
    config_path: Optional path to config file. Uses default if not provided.

Returns:
    Loaded configuration object."""
    ...
def save_config(config: Config, config_path: Path | None = None) -> None:
    """Save configuration to file.

Args:
    config: Configuration to save.
    config_path: Optional path to save to. Uses default if not provided."""
    ...
def _migrate_config(data: dict) -> dict:
    """Migrate old config formats to current."""
    ...
