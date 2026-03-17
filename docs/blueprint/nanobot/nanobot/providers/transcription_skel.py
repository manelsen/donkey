"""Voice transcription provider using Groq."""
import os
from pathlib import Path
import httpx
from loguru import logger
class GroqTranscriptionProvider:
    """Voice transcription provider using Groq's Whisper API.

Groq offers extremely fast transcription with a generous free tier."""
    def __init__(self, api_key: str | None = None):
        ...
    async def transcribe(self, file_path: str | Path) -> str:
        """Transcribe an audio file using Groq.

Args:
    file_path: Path to the audio file.

Returns:
    Transcribed text."""
        ...
