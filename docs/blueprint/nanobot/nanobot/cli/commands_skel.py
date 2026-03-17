"""CLI commands for nanobot."""
import asyncio
from contextlib import contextmanager, nullcontext
import os
import select
import signal
import sys
from pathlib import Path
from typing import Any
import typer
from prompt_toolkit import print_formatted_text
from prompt_toolkit import PromptSession
from prompt_toolkit.formatted_text import ANSI, HTML
from prompt_toolkit.history import FileHistory
from prompt_toolkit.patch_stdout import patch_stdout
from prompt_toolkit.application import run_in_terminal
from rich.console import Console
from rich.markdown import Markdown
from rich.table import Table
from rich.text import Text
from nanobot import __logo__, __version__
from nanobot.config.paths import get_workspace_path
from nanobot.config.schema import Config
from nanobot.utils.helpers import sync_workspace_templates
def _flush_pending_tty_input() -> None:
    """Drop unread keypresses typed while the model was generating output."""
    ...
def _restore_terminal() -> None:
    """Restore terminal to its original state (echo, line buffering, etc.)."""
    ...
def _init_prompt_session() -> None:
    """Create the prompt_toolkit session with persistent file history."""
    ...
def _make_console() -> Console:
    ...
def _render_interactive_ansi(render_fn) -> str:
    """Render Rich output to ANSI so prompt_toolkit can print it safely."""
    ...
def _print_agent_response(response: str, render_markdown: bool) -> None:
    """Render assistant response with consistent terminal styling."""
    ...
async def _print_interactive_line(text: str) -> None:
    """Print async interactive updates with prompt_toolkit-safe Rich styling."""
    ...
async def _print_interactive_response(response: str, render_markdown: bool) -> None:
    """Print async interactive replies with prompt_toolkit-safe Rich styling."""
    ...
class _ThinkingSpinner:
    """Spinner wrapper with pause support for clean progress output."""
    def __init__(self, enabled: bool):
        ...
    def __enter__(self):
        ...
    def __exit__(self, *exc):
        ...
    @contextmanager
    def pause(self):
        """Temporarily stop spinner while printing progress."""
        ...
def _print_cli_progress_line(text: str, thinking: _ThinkingSpinner | None) -> None:
    """Print a CLI progress line, pausing the spinner if needed."""
    ...
async def _print_interactive_progress_line(text: str, thinking: _ThinkingSpinner | None) -> None:
    """Print an interactive progress line, pausing the spinner if needed."""
    ...
def _is_exit_command(command: str) -> bool:
    """Return True when input should end interactive chat."""
    ...
async def _read_interactive_input_async() -> str:
    """Read user input using prompt_toolkit (handles paste, history, display).

prompt_toolkit natively handles:
- Multiline paste (bracketed paste mode)
- History navigation (up/down arrows)
- Clean display (no ghost characters or artifacts)"""
    ...
def version_callback(value: bool):
    ...
@app.callback()
def main(version: bool = typer.Option(None, '--version', '-v', callback=version_callback, is_eager=True)):
    """nanobot - Personal AI Assistant."""
    ...
@app.command()
def onboard():
    """Initialize nanobot configuration and workspace."""
    ...
def _merge_missing_defaults(existing: Any, defaults: Any) -> Any:
    """Recursively fill in missing values from defaults without overwriting user config."""
    ...
def _onboard_plugins(config_path: Path) -> None:
    """Inject default config for all discovered channels (built-in + plugins)."""
    ...
def _make_provider(config: Config):
    """Create the appropriate LLM provider from config."""
    ...
def _load_runtime_config(config: str | None = None, workspace: str | None = None) -> Config:
    """Load config and optionally override the active workspace."""
    ...
def _print_deprecated_memory_window_notice(config: Config) -> None:
    """Warn when running with old memoryWindow-only config."""
    ...
@app.command()
def gateway(port: int | None = typer.Option(None, '--port', '-p', help='Gateway port'), workspace: str | None = typer.Option(None, '--workspace', '-w', help='Workspace directory'), verbose: bool = typer.Option(False, '--verbose', '-v', help='Verbose output'), config: str | None = typer.Option(None, '--config', '-c', help='Path to config file')):
    """Start the nanobot gateway."""
    ...
@app.command()
def agent(message: str = typer.Option(None, '--message', '-m', help='Message to send to the agent'), session_id: str = typer.Option('cli:direct', '--session', '-s', help='Session ID'), workspace: str | None = typer.Option(None, '--workspace', '-w', help='Workspace directory'), config: str | None = typer.Option(None, '--config', '-c', help='Config file path'), markdown: bool = typer.Option(True, '--markdown/--no-markdown', help='Render assistant output as Markdown'), logs: bool = typer.Option(False, '--logs/--no-logs', help='Show nanobot runtime logs during chat')):
    """Interact with the agent directly."""
    ...
@channels_app.command('status')
def channels_status():
    """Show channel status."""
    ...
def _get_bridge_dir() -> Path:
    """Get the bridge directory, setting it up if needed."""
    ...
@channels_app.command('login')
def channels_login():
    """Link device via QR code."""
    ...
@plugins_app.command('list')
def plugins_list():
    """List all discovered channels (built-in and plugins)."""
    ...
@app.command()
def status():
    """Show nanobot status."""
    ...
def _register_login(name: str):
    ...
@provider_app.command('login')
def provider_login(provider: str = typer.Argument(..., help="OAuth provider (e.g. 'openai-codex', 'github-copilot')")):
    """Authenticate with an OAuth provider."""
    ...
@_register_login('openai_codex')
def _login_openai_codex() -> None:
    ...
@_register_login('github_copilot')
def _login_github_copilot() -> None:
    ...
