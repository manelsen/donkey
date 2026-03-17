"""Skill Packager - Creates a distributable .skill file of a skill folder

Usage:
    python package_skill.py <path/to/skill-folder> [output-directory]

Example:
    python package_skill.py skills/public/my-skill
    python package_skill.py skills/public/my-skill ./dist"""
import sys
import zipfile
from pathlib import Path
from quick_validate import validate_skill
def _is_within(path: Path, root: Path) -> bool:
    ...
def _cleanup_partial_archive(skill_filename: Path) -> None:
    ...
def package_skill(skill_path, output_dir = None):
    """Package a skill folder into a .skill file.

Args:
    skill_path: Path to the skill folder
    output_dir: Optional output directory for the .skill file (defaults to current directory)

Returns:
    Path to the created .skill file, or None if error"""
    ...
def main():
    ...
