"""Skills loader for agent capabilities."""
import json
import os
import re
import shutil
from pathlib import Path
class SkillsLoader:
    """Loader for agent skills.

Skills are markdown files (SKILL.md) that teach the agent how to use
specific tools or perform certain tasks."""
    def __init__(self, workspace: Path, builtin_skills_dir: Path | None = None):
        ...
    def list_skills(self, filter_unavailable: bool = True) -> list[dict[str, str]]:
        """List all available skills.

Args:
    filter_unavailable: If True, filter out skills with unmet requirements.

Returns:
    List of skill info dicts with 'name', 'path', 'source'."""
        ...
    def load_skill(self, name: str) -> str | None:
        """Load a skill by name.

Args:
    name: Skill name (directory name).

Returns:
    Skill content or None if not found."""
        ...
    def load_skills_for_context(self, skill_names: list[str]) -> str:
        """Load specific skills for inclusion in agent context.

Args:
    skill_names: List of skill names to load.

Returns:
    Formatted skills content."""
        ...
    def build_skills_summary(self) -> str:
        """Build a summary of all skills (name, description, path, availability).

This is used for progressive loading - the agent can read the full
skill content using read_file when needed.

Returns:
    XML-formatted skills summary."""
        ...
    def _get_missing_requirements(self, skill_meta: dict) -> str:
        """Get a description of missing requirements."""
        ...
    def _get_skill_description(self, name: str) -> str:
        """Get the description of a skill from its frontmatter."""
        ...
    def _strip_frontmatter(self, content: str) -> str:
        """Remove YAML frontmatter from markdown content."""
        ...
    def _parse_nanobot_metadata(self, raw: str) -> dict:
        """Parse skill metadata JSON from frontmatter (supports nanobot and openclaw keys)."""
        ...
    def _check_requirements(self, skill_meta: dict) -> bool:
        """Check if skill requirements are met (bins, env vars)."""
        ...
    def _get_skill_meta(self, name: str) -> dict:
        """Get nanobot metadata for a skill (cached in frontmatter)."""
        ...
    def get_always_skills(self) -> list[str]:
        """Get skills marked as always=true that meet requirements."""
        ...
    def get_skill_metadata(self, name: str) -> dict | None:
        """Get metadata from a skill's frontmatter.

Args:
    name: Skill name.

Returns:
    Metadata dict or None."""
        ...
