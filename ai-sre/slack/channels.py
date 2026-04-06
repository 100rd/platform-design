"""Channel routing for AI SRE Slack advisories.

Maps agent roles and advisory types to the appropriate Slack channels.
"""

import logging
import os
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)


@dataclass
class ChannelConfig:
    """Configuration for a Slack channel."""

    name: str
    channel_id: str = ""
    description: str = ""


# Default channel architecture as specified in issue #112
DEFAULT_CHANNELS: dict[str, ChannelConfig] = {
    "alerts": ChannelConfig(
        name="sre-alerts",
        description="All automated advisories from agents (read-only for humans)",
    ),
    "incidents": ChannelConfig(
        name="sre-incidents",
        description="Active incident threads (agent + human collaboration)",
    ),
    "cost": ChannelConfig(
        name="sre-cost",
        description="Weekly cost reports and optimization advisories",
    ),
    "capacity": ChannelConfig(
        name="sre-capacity",
        description="Capacity planning reports",
    ),
    "gpu-health": ChannelConfig(
        name="sre-gpu-health",
        description="GPU fleet health advisories",
    ),
    "chaos": ChannelConfig(
        name="sre-chaos",
        description="Chaos experiment proposals and results",
    ),
}


class ChannelRouter:
    """Routes advisories to appropriate Slack channels based on agent role."""

    def __init__(self) -> None:
        self.channels = DEFAULT_CHANNELS.copy()
        self._load_channel_ids_from_env()

    def _load_channel_ids_from_env(self) -> None:
        """Load channel IDs from environment variables.

        Channel IDs are configured via ConfigMap:
        SLACK_CHANNEL_ALERTS=C0123456789
        SLACK_CHANNEL_INCIDENTS=C0123456790
        etc.
        """
        env_mapping = {
            "alerts": "SLACK_CHANNEL_ALERTS",
            "incidents": "SLACK_CHANNEL_INCIDENTS",
            "cost": "SLACK_CHANNEL_COST",
            "capacity": "SLACK_CHANNEL_CAPACITY",
            "gpu-health": "SLACK_CHANNEL_GPU_HEALTH",
            "chaos": "SLACK_CHANNEL_CHAOS",
        }
        for key, env_var in env_mapping.items():
            channel_id = os.environ.get(env_var, "")
            if channel_id and key in self.channels:
                self.channels[key].channel_id = channel_id

    def get_channel_for_agent(self, agent_role: str) -> str:
        """Return the Slack channel ID for a given agent role.

        Routing rules:
        - gpu-health          -> #sre-gpu-health
        - cost-optimization   -> #sre-cost
        - capacity-planning   -> #sre-capacity
        - chaos-engineering   -> #sre-chaos
        - incident-response   -> #sre-incidents
        - All others          -> #sre-alerts
        """
        role_to_channel: dict[str, str] = {
            "gpu-health": "gpu-health",
            "cost-optimization": "cost",
            "capacity-planning": "capacity",
            "chaos-engineering": "chaos",
            "incident-response": "incidents",
        }

        channel_key = role_to_channel.get(agent_role, "alerts")
        channel = self.channels.get(channel_key)
        if channel and channel.channel_id:
            return channel.channel_id

        # Fallback to alerts channel
        fallback = self.channels.get("alerts")
        return fallback.channel_id if fallback else ""

    def get_channel_id(self, channel_key: str) -> str:
        """Get channel ID by logical name."""
        channel = self.channels.get(channel_key)
        return channel.channel_id if channel else ""
