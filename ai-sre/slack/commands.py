"""Slash command handlers for the AI SRE Slack app.

Implements /sre <subcommand> for interactive SRE operations.
"""

import logging
from typing import Any

import structlog
from slack_bolt.app.async_app import AsyncApp

from .blocks import build_status_blocks
from .channels import ChannelRouter

logger = structlog.get_logger()


def register_commands(app: AsyncApp, channel_router: ChannelRouter) -> None:
    """Register all /sre slash command handlers."""

    @app.command("/sre")
    async def handle_sre_command(ack: Any, command: Any, respond: Any) -> None:
        """Dispatch /sre subcommands.

        Supported subcommands:
        - status         Current system health across all clusters
        - investigate    Trigger ad-hoc investigation
        - cost           Current cost summary
        - capacity       Current capacity summary
        - gpu-health     GPU fleet health snapshot
        - runbook        Start runbook execution
        - history        Search incident history
        """
        await ack()

        text = command.get("text", "").strip()
        parts = text.split(maxsplit=1)
        subcommand = parts[0] if parts else "help"
        args = parts[1] if len(parts) > 1 else ""

        handlers = {
            "status": _handle_status,
            "investigate": _handle_investigate,
            "cost": _handle_cost,
            "capacity": _handle_capacity,
            "gpu-health": _handle_gpu_health,
            "runbook": _handle_runbook,
            "history": _handle_history,
            "help": _handle_help,
        }

        handler = handlers.get(subcommand, _handle_unknown)
        await handler(respond, args, command, channel_router)

        logger.info(
            "slash_command_handled",
            subcommand=subcommand,
            user=command.get("user_id"),
        )


async def _handle_status(
    respond: Any, args: str, command: Any, channel_router: ChannelRouter
) -> None:
    """Handle /sre status — show system health."""
    # In production, this queries the orchestrator API for live data.
    # Placeholder response demonstrating Block Kit format.
    clusters = [
        {"name": "platform (hub)", "health": "healthy"},
        {"name": "gpu-inference", "health": "healthy"},
        {"name": "gpu-analysis", "health": "healthy"},
        {"name": "blockchain", "health": "healthy"},
    ]
    blocks = build_status_blocks(
        clusters=clusters,
        active_investigations=0,
        agents_online=8,
    )
    await respond(blocks=blocks)


async def _handle_investigate(
    respond: Any, args: str, command: Any, channel_router: ChannelRouter
) -> None:
    """Handle /sre investigate <description> — trigger ad-hoc investigation."""
    if not args:
        await respond(
            text="Usage: `/sre investigate <description of the issue>`"
        )
        return

    user = command.get("user_id", "unknown")
    await respond(
        text=(
            f":mag: Starting investigation requested by <@{user}>:\n"
            f"> {args}\n\n"
            "The SRE orchestrator is analyzing the situation. "
            "Results will be posted to this thread."
        ),
    )
    logger.info("investigation_requested", description=args, user=user)


async def _handle_cost(
    respond: Any, args: str, command: Any, channel_router: ChannelRouter
) -> None:
    """Handle /sre cost — show cost summary."""
    await respond(
        text=(
            ":money_with_wings: *Cost Summary*\n"
            "Querying cost optimization agent for current data...\n"
            "Results will be posted to #sre-cost."
        ),
    )


async def _handle_capacity(
    respond: Any, args: str, command: Any, channel_router: ChannelRouter
) -> None:
    """Handle /sre capacity — show capacity summary."""
    await respond(
        text=(
            ":bar_chart: *Capacity Summary*\n"
            "Querying capacity planning agent for current data...\n"
            "Results will be posted to #sre-capacity."
        ),
    )


async def _handle_gpu_health(
    respond: Any, args: str, command: Any, channel_router: ChannelRouter
) -> None:
    """Handle /sre gpu-health — show GPU fleet health."""
    await respond(
        text=(
            ":desktop_computer: *GPU Fleet Health*\n"
            "Querying GPU health agent for fleet status...\n"
            "Results will be posted to #sre-gpu-health."
        ),
    )


async def _handle_runbook(
    respond: Any, args: str, command: Any, channel_router: ChannelRouter
) -> None:
    """Handle /sre runbook <name> — start runbook execution."""
    if not args:
        await respond(
            text="Usage: `/sre runbook <runbook-name>`\nExample: `/sre runbook gpu-node-unhealthy`"
        )
        return

    await respond(
        text=(
            f":notebook_with_decorative_cover: Starting runbook `{args}`\n"
            "The runbook automation agent will guide you through each step. "
            "Approval-required steps will prompt for confirmation."
        ),
    )


async def _handle_history(
    respond: Any, args: str, command: Any, channel_router: ChannelRouter
) -> None:
    """Handle /sre history <query> — search incident history."""
    if not args:
        await respond(
            text="Usage: `/sre history <search query>`\nExample: `/sre history GPU XID errors`"
        )
        return

    await respond(
        text=(
            f":mag_right: Searching incident history for: _{args}_\n"
            "Querying the knowledge base..."
        ),
    )


async def _handle_help(
    respond: Any, args: str, command: Any, channel_router: ChannelRouter
) -> None:
    """Handle /sre help — show available subcommands."""
    await respond(
        text=(
            "*AI SRE Bot Commands*\n\n"
            "`/sre status` — Current system health across all clusters\n"
            "`/sre investigate <description>` — Trigger ad-hoc investigation\n"
            "`/sre cost` — Current cost summary\n"
            "`/sre capacity` — Current capacity summary\n"
            "`/sre gpu-health` — GPU fleet health snapshot\n"
            "`/sre runbook <name>` — Start runbook execution\n"
            "`/sre history <query>` — Search incident history\n"
            "`/sre help` — Show this help message"
        ),
    )


async def _handle_unknown(
    respond: Any, args: str, command: Any, channel_router: ChannelRouter
) -> None:
    """Handle unknown subcommand."""
    await respond(
        text="Unknown subcommand. Use `/sre help` to see available commands."
    )
