"""Provider Registry — single source of truth for LLM provider metadata.

Adding a new provider:
  1. Add a ProviderSpec to PROVIDERS below.
  2. Add a field to ProvidersConfig in config/schema.py.
  Done. Env vars, prefixing, config matching, status display all derive from here.

Order matters — it controls match priority and fallback. Gateways first.
Every entry writes out all fields so you can copy-paste as a template."""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any
@dataclass(frozen=True)
class ProviderSpec:
    """One LLM provider's metadata. See PROVIDERS below for real examples.

Placeholders in env_extras values:
  {api_key}  — the user's API key
  {api_base} — api_base from config, or this spec's default_api_base"""
    name: str
    keywords: tuple[str, ...]
    env_key: str
    display_name: str = ''
    litellm_prefix: str = ''
    skip_prefixes: tuple[str, ...] = ()
    env_extras: tuple[tuple[str, str], ...] = ()
    is_gateway: bool = False
    is_local: bool = False
    detect_by_key_prefix: str = ''
    detect_by_base_keyword: str = ''
    default_api_base: str = ''
    strip_model_prefix: bool = False
    litellm_kwargs: dict[str, Any] = field(default_factory=dict)
    model_overrides: tuple[tuple[str, dict[str, Any]], ...] = ()
    is_oauth: bool = False
    is_direct: bool = False
    supports_prompt_caching: bool = False
    @property
    def label(self) -> str:
        ...
def find_by_model(model: str) -> ProviderSpec | None:
    """Match a standard provider by model-name keyword (case-insensitive).
Skips gateways/local — those are matched by api_key/api_base instead."""
    ...
def find_gateway(provider_name: str | None = None, api_key: str | None = None, api_base: str | None = None) -> ProviderSpec | None:
    """Detect gateway/local provider.

Priority:
  1. provider_name — if it maps to a gateway/local spec, use it directly.
  2. api_key prefix — e.g. "sk-or-" → OpenRouter.
  3. api_base keyword — e.g. "aihubmix" in URL → AiHubMix.

A standard provider with a custom api_base (e.g. DeepSeek behind a proxy)
will NOT be mistaken for vLLM — the old fallback is gone."""
    ...
def find_by_name(name: str) -> ProviderSpec | None:
    """Find a provider spec by config field name, e.g. "dashscope"."""
    ...
