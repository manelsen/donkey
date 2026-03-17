"""Configuration schema using Pydantic."""
from pathlib import Path
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel
from pydantic_settings import BaseSettings
class Base(BaseModel):
    """Base model that accepts both camelCase and snake_case keys."""
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)
class ChannelsConfig(Base):
    """Configuration for chat channels.

Built-in and plugin channel configs are stored as extra fields (dicts).
Each channel parses its own config in __init__."""
    model_config = ConfigDict(extra='allow')
    send_progress: bool = True
    send_tool_hints: bool = False
class AgentDefaults(Base):
    """Default agent configuration."""
    workspace: str = '~/.nanobot/workspace'
    model: str = 'anthropic/claude-opus-4-5'
    provider: str = 'auto'
    max_tokens: int = 8192
    context_window_tokens: int = 65536
    temperature: float = 0.1
    max_tool_iterations: int = 40
    memory_window: int | None = Field(default=None, exclude=True)
    reasoning_effort: str | None = None
    @property
    def should_warn_deprecated_memory_window(self) -> bool:
        """Return True when old memoryWindow is present without contextWindowTokens."""
        ...
class AgentsConfig(Base):
    """Agent configuration."""
    defaults: AgentDefaults = Field(default_factory=AgentDefaults)
class ProviderConfig(Base):
    """LLM provider configuration."""
    api_key: str = ''
    api_base: str | None = None
    extra_headers: dict[str, str] | None = None
class ProvidersConfig(Base):
    """Configuration for LLM providers."""
    custom: ProviderConfig = Field(default_factory=ProviderConfig)
    azure_openai: ProviderConfig = Field(default_factory=ProviderConfig)
    anthropic: ProviderConfig = Field(default_factory=ProviderConfig)
    openai: ProviderConfig = Field(default_factory=ProviderConfig)
    openrouter: ProviderConfig = Field(default_factory=ProviderConfig)
    deepseek: ProviderConfig = Field(default_factory=ProviderConfig)
    groq: ProviderConfig = Field(default_factory=ProviderConfig)
    zhipu: ProviderConfig = Field(default_factory=ProviderConfig)
    dashscope: ProviderConfig = Field(default_factory=ProviderConfig)
    vllm: ProviderConfig = Field(default_factory=ProviderConfig)
    ollama: ProviderConfig = Field(default_factory=ProviderConfig)
    gemini: ProviderConfig = Field(default_factory=ProviderConfig)
    moonshot: ProviderConfig = Field(default_factory=ProviderConfig)
    minimax: ProviderConfig = Field(default_factory=ProviderConfig)
    aihubmix: ProviderConfig = Field(default_factory=ProviderConfig)
    siliconflow: ProviderConfig = Field(default_factory=ProviderConfig)
    volcengine: ProviderConfig = Field(default_factory=ProviderConfig)
    volcengine_coding_plan: ProviderConfig = Field(default_factory=ProviderConfig)
    byteplus: ProviderConfig = Field(default_factory=ProviderConfig)
    byteplus_coding_plan: ProviderConfig = Field(default_factory=ProviderConfig)
    openai_codex: ProviderConfig = Field(default_factory=ProviderConfig)
    github_copilot: ProviderConfig = Field(default_factory=ProviderConfig)
class HeartbeatConfig(Base):
    """Heartbeat service configuration."""
    enabled: bool = True
    interval_s: int = 30 * 60
class GatewayConfig(Base):
    """Gateway/server configuration."""
    host: str = '0.0.0.0'
    port: int = 18790
    heartbeat: HeartbeatConfig = Field(default_factory=HeartbeatConfig)
class WebSearchConfig(Base):
    """Web search tool configuration."""
    provider: str = 'brave'
    api_key: str = ''
    base_url: str = ''
    max_results: int = 5
class WebToolsConfig(Base):
    """Web tools configuration."""
    proxy: str | None = None
    search: WebSearchConfig = Field(default_factory=WebSearchConfig)
class ExecToolConfig(Base):
    """Shell exec tool configuration."""
    timeout: int = 60
    path_append: str = ''
class MCPServerConfig(Base):
    """MCP server connection configuration (stdio or HTTP)."""
    type: Literal['stdio', 'sse', 'streamableHttp'] | None = None
    command: str = ''
    args: list[str] = Field(default_factory=list)
    env: dict[str, str] = Field(default_factory=dict)
    url: str = ''
    headers: dict[str, str] = Field(default_factory=dict)
    tool_timeout: int = 30
    enabled_tools: list[str] = Field(default_factory=lambda: ['*'])
class ToolsConfig(Base):
    """Tools configuration."""
    web: WebToolsConfig = Field(default_factory=WebToolsConfig)
    exec: ExecToolConfig = Field(default_factory=ExecToolConfig)
    restrict_to_workspace: bool = False
    mcp_servers: dict[str, MCPServerConfig] = Field(default_factory=dict)
class Config(BaseSettings):
    """Root configuration for nanobot."""
    agents: AgentsConfig = Field(default_factory=AgentsConfig)
    channels: ChannelsConfig = Field(default_factory=ChannelsConfig)
    providers: ProvidersConfig = Field(default_factory=ProvidersConfig)
    gateway: GatewayConfig = Field(default_factory=GatewayConfig)
    tools: ToolsConfig = Field(default_factory=ToolsConfig)
    @property
    def workspace_path(self) -> Path:
        """Get expanded workspace path."""
        ...
    def _match_provider(self, model: str | None = None) -> tuple['ProviderConfig | None', str | None]:
        """Match provider config and its registry name. Returns (config, spec_name)."""
        ...
    def get_provider(self, model: str | None = None) -> ProviderConfig | None:
        """Get matched provider config (api_key, api_base, extra_headers). Falls back to first available."""
        ...
    def get_provider_name(self, model: str | None = None) -> str | None:
        """Get the registry name of the matched provider (e.g. "deepseek", "openrouter")."""
        ...
    def get_api_key(self, model: str | None = None) -> str | None:
        """Get API key for the given model. Falls back to first available key."""
        ...
    def get_api_base(self, model: str | None = None) -> str | None:
        """Get API base URL for the given model. Applies default URLs for gateway/local providers."""
        ...
    model_config = ConfigDict(env_prefix='NANOBOT_', env_nested_delimiter='__')
