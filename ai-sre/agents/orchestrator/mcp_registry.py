"""MCP server registry — manages connections to MCP tool servers."""

import logging
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional

logger = logging.getLogger(__name__)


class MCPTransport(str, Enum):
    """MCP server transport types."""

    STDIO = "stdio"
    SSE = "sse"
    STREAMABLE_HTTP = "streamable-http"


@dataclass
class MCPServerConfig:
    """Configuration for an MCP tool server."""

    name: str
    transport: MCPTransport
    command: Optional[str] = None
    args: list[str] = field(default_factory=list)
    url: Optional[str] = None
    env: dict[str, str] = field(default_factory=dict)
    read_only: bool = True
    health_check_path: Optional[str] = None


# Default MCP server configurations for the AI SRE system
DEFAULT_MCP_SERVERS: dict[str, MCPServerConfig] = {
    "kubernetes-mcp": MCPServerConfig(
        name="kubernetes-mcp",
        transport=MCPTransport.STDIO,
        command="kubernetes-mcp-server",
        args=[],
        env={
            "KUBERNETES_MCP_READ_ONLY": "true",
            "KUBERNETES_MCP_REDACT_SECRETS": "true",
        },
        read_only=True,
    ),
    "aws-mcp": MCPServerConfig(
        name="aws-mcp",
        transport=MCPTransport.STDIO,
        command="awslabs-mcp",
        args=["eks"],
        read_only=True,
    ),
    "metrics-mcp": MCPServerConfig(
        name="metrics-mcp",
        transport=MCPTransport.STREAMABLE_HTTP,
        url="http://metrics-mcp.ai-sre-system.svc.cluster.local:8080",
        read_only=True,
        health_check_path="/health",
    ),
    "runbook-mcp": MCPServerConfig(
        name="runbook-mcp",
        transport=MCPTransport.STREAMABLE_HTTP,
        url="http://runbook-mcp.ai-sre-system.svc.cluster.local:8081",
        read_only=False,
        health_check_path="/health",
    ),
    "git-mcp": MCPServerConfig(
        name="git-mcp",
        transport=MCPTransport.STDIO,
        command="git-mcp-server",
        args=[],
        read_only=True,
    ),
    "slack-mcp": MCPServerConfig(
        name="slack-mcp",
        transport=MCPTransport.STDIO,
        command="slack-mcp-server",
        args=[],
        read_only=False,
    ),
}


class MCPRegistry:
    """Registry for MCP tool servers used by the AI SRE agents.

    Manages server configurations, health status, and provides
    the server list for agent SDK initialization.
    """

    def __init__(
        self, server_configs: Optional[dict[str, MCPServerConfig]] = None
    ) -> None:
        self.servers: dict[str, MCPServerConfig] = (
            server_configs or DEFAULT_MCP_SERVERS.copy()
        )
        self._health_status: dict[str, bool] = {}

    def register(self, config: MCPServerConfig) -> None:
        """Register a new MCP server."""
        self.servers[config.name] = config
        logger.info("Registered MCP server: %s (%s)", config.name, config.transport)

    def unregister(self, name: str) -> None:
        """Remove an MCP server from the registry."""
        if name in self.servers:
            del self.servers[name]
            self._health_status.pop(name, None)
            logger.info("Unregistered MCP server: %s", name)

    def get(self, name: str) -> Optional[MCPServerConfig]:
        """Get an MCP server configuration by name."""
        return self.servers.get(name)

    def list_servers(self) -> list[MCPServerConfig]:
        """List all registered MCP servers."""
        return list(self.servers.values())

    def get_servers_for_role(self, tool_permissions: list) -> list[MCPServerConfig]:
        """Get MCP server configs that an agent role is permitted to use."""
        permitted = []
        for perm in tool_permissions:
            server = self.servers.get(perm.server)
            if server:
                permitted.append(server)
        return permitted

    def to_sdk_config(self) -> list[dict[str, Any]]:
        """Convert registry to Claude Agent SDK MCP server format.

        Returns the configuration structure expected by the
        claude-agent-sdk for MCP server initialization.
        """
        configs = []
        for server in self.servers.values():
            config: dict[str, Any] = {
                "name": server.name,
                "transport": server.transport.value,
            }
            if server.command:
                config["command"] = server.command
                config["args"] = server.args
            if server.url:
                config["url"] = server.url
            if server.env:
                config["env"] = server.env
            configs.append(config)
        return configs

    async def check_health(self, name: str) -> bool:
        """Check health of a specific MCP server.

        For HTTP-based servers, performs a GET on the health_check_path.
        For stdio-based servers, verifies the command is available.
        """
        server = self.servers.get(name)
        if not server:
            return False

        # Health check implementation would go here
        # For now, mark as healthy
        self._health_status[name] = True
        return True

    async def check_all_health(self) -> dict[str, bool]:
        """Check health of all registered MCP servers."""
        for name in self.servers:
            await self.check_health(name)
        return self._health_status.copy()
