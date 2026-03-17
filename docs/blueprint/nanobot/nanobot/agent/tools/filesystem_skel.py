"""File system tools: read, write, edit, list."""
import difflib
from pathlib import Path
from typing import Any
from nanobot.agent.tools.base import Tool
def _resolve_path(path: str, workspace: Path | None = None, allowed_dir: Path | None = None, extra_allowed_dirs: list[Path] | None = None) -> Path:
    """Resolve path against workspace (if relative) and enforce directory restriction."""
    ...
def _is_under(path: Path, directory: Path) -> bool:
    ...
class _FsTool(Tool):
    """Shared base for filesystem tools — common init and path resolution."""
    def __init__(self, workspace: Path | None = None, allowed_dir: Path | None = None, extra_allowed_dirs: list[Path] | None = None):
        ...
    def _resolve(self, path: str) -> Path:
        ...
class ReadFileTool(_FsTool):
    """Read file contents with optional line-based pagination."""
    _MAX_CHARS = 128000
    _DEFAULT_LIMIT = 2000
    @property
    def name(self) -> str:
        ...
    @property
    def description(self) -> str:
        ...
    @property
    def parameters(self) -> dict[str, Any]:
        ...
    async def execute(self, path: str, offset: int = 1, limit: int | None = None, **kwargs: Any) -> str:
        ...
class WriteFileTool(_FsTool):
    """Write content to a file."""
    @property
    def name(self) -> str:
        ...
    @property
    def description(self) -> str:
        ...
    @property
    def parameters(self) -> dict[str, Any]:
        ...
    async def execute(self, path: str, content: str, **kwargs: Any) -> str:
        ...
def _find_match(content: str, old_text: str) -> tuple[str | None, int]:
    """Locate old_text in content: exact first, then line-trimmed sliding window.

Both inputs should use LF line endings (caller normalises CRLF).
Returns (matched_fragment, count) or (None, 0)."""
    ...
class EditFileTool(_FsTool):
    """Edit a file by replacing text with fallback matching."""
    @property
    def name(self) -> str:
        ...
    @property
    def description(self) -> str:
        ...
    @property
    def parameters(self) -> dict[str, Any]:
        ...
    async def execute(self, path: str, old_text: str, new_text: str, replace_all: bool = False, **kwargs: Any) -> str:
        ...
    @staticmethod
    def _not_found_msg(old_text: str, content: str, path: str) -> str:
        ...
class ListDirTool(_FsTool):
    """List directory contents with optional recursion."""
    _DEFAULT_MAX = 200
    _IGNORE_DIRS = {'.git', 'node_modules', '__pycache__', '.venv', 'venv', 'dist', 'build', '.tox', '.mypy_cache', '.pytest_cache', '.ruff_cache', '.coverage', 'htmlcov'}
    @property
    def name(self) -> str:
        ...
    @property
    def description(self) -> str:
        ...
    @property
    def parameters(self) -> dict[str, Any]:
        ...
    async def execute(self, path: str, recursive: bool = False, max_entries: int | None = None, **kwargs: Any) -> str:
        ...
