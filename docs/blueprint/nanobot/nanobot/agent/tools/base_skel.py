"""Base class for agent tools."""
from abc import ABC, abstractmethod
from typing import Any
class Tool(ABC):
    """Abstract base class for agent tools.

Tools are capabilities that the agent can use to interact with
the environment, such as reading files, executing commands, etc."""
    _TYPE_MAP = {'string': str, 'integer': int, 'number': (int, float), 'boolean': bool, 'array': list, 'object': dict}
    @property
    @abstractmethod
    def name(self) -> str:
        """Tool name used in function calls."""
        ...
    @property
    @abstractmethod
    def description(self) -> str:
        """Description of what the tool does."""
        ...
    @property
    @abstractmethod
    def parameters(self) -> dict[str, Any]:
        """JSON Schema for tool parameters."""
        ...
    @abstractmethod
    async def execute(self, **kwargs: Any) -> str:
        """Execute the tool with given parameters.

Args:
    **kwargs: Tool-specific parameters.

Returns:
    String result of the tool execution."""
        ...
    def cast_params(self, params: dict[str, Any]) -> dict[str, Any]:
        """Apply safe schema-driven casts before validation."""
        ...
    def _cast_object(self, obj: Any, schema: dict[str, Any]) -> dict[str, Any]:
        """Cast an object (dict) according to schema."""
        ...
    def _cast_value(self, val: Any, schema: dict[str, Any]) -> Any:
        """Cast a single value according to schema."""
        ...
    def validate_params(self, params: dict[str, Any]) -> list[str]:
        """Validate tool parameters against JSON schema. Returns error list (empty if valid)."""
        ...
    def _validate(self, val: Any, schema: dict[str, Any], path: str) -> list[str]:
        ...
    def to_schema(self) -> dict[str, Any]:
        """Convert tool to OpenAI function schema format."""
        ...
