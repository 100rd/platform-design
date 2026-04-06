"""Runbook MCP Server — operational runbook engine with approval workflows."""

import logging
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import yaml
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

logger = logging.getLogger(__name__)

RUNBOOK_DIR = Path(os.environ.get("RUNBOOK_DIR", "/etc/ai-sre/runbooks"))
APPROVAL_CALLBACK_URL = os.environ.get("APPROVAL_CALLBACK_URL", "")


@dataclass
class RunbookStep:
    """A single step in a runbook."""

    step_id: int
    title: str
    command_type: str  # kubectl, query, shell
    command: str
    auto_executable: bool = False
    approval_required: bool = False


@dataclass
class Runbook:
    """Parsed runbook with frontmatter and steps."""

    id: str
    name: str
    category: str
    severity: str
    clusters: list[str] = field(default_factory=list)
    symptoms: list[str] = field(default_factory=list)
    steps: list[RunbookStep] = field(default_factory=list)
    raw_content: str = ""


@dataclass
class ExecutionResult:
    """Result of executing a runbook step."""

    runbook_id: str
    step_id: int
    status: str  # success, failed, pending_approval, skipped
    output: str = ""
    executed_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    approved_by: Optional[str] = None


class RunbookStore:
    """Manages loading and searching runbooks from the filesystem."""

    def __init__(self, runbook_dir: Path) -> None:
        self.runbook_dir = runbook_dir
        self.runbooks: dict[str, Runbook] = {}
        self._load_runbooks()

    def _load_runbooks(self) -> None:
        """Load all runbook markdown files from the runbook directory."""
        if not self.runbook_dir.exists():
            logger.warning("Runbook directory does not exist: %s", self.runbook_dir)
            return

        for md_file in self.runbook_dir.glob("**/*.md"):
            try:
                runbook = self._parse_runbook(md_file)
                if runbook:
                    self.runbooks[runbook.id] = runbook
            except Exception as e:
                logger.error("Failed to parse runbook %s: %s", md_file, e)

        logger.info("Loaded %d runbooks", len(self.runbooks))

    def _parse_runbook(self, path: Path) -> Optional[Runbook]:
        """Parse a runbook markdown file with YAML frontmatter."""
        content = path.read_text()
        if not content.startswith("---"):
            return None

        parts = content.split("---", 2)
        if len(parts) < 3:
            return None

        frontmatter = yaml.safe_load(parts[1])
        body = parts[2]

        auto_steps = set(frontmatter.get("auto_executable_steps", []))
        approval_steps = set(frontmatter.get("approval_required_steps", []))

        # Parse steps from markdown
        steps = []
        current_step_id = 0
        current_title = ""
        current_commands: list[tuple[str, str]] = []
        lines = body.split("\n")

        for line in lines:
            if line.startswith("### Step "):
                if current_step_id > 0 and current_commands:
                    for cmd_type, cmd in current_commands:
                        steps.append(RunbookStep(
                            step_id=current_step_id,
                            title=current_title,
                            command_type=cmd_type,
                            command=cmd,
                            auto_executable=current_step_id in auto_steps,
                            approval_required=current_step_id in approval_steps,
                        ))
                # Parse step number from "### Step N: Title"
                try:
                    step_part = line.split(":", 1)
                    current_step_id = int(step_part[0].replace("### Step ", "").strip())
                    current_title = step_part[1].strip() if len(step_part) > 1 else ""
                except (ValueError, IndexError):
                    current_step_id = 0
                current_commands = []
            elif line.startswith("```") and current_step_id > 0:
                cmd_type = line.replace("```", "").strip()
                if cmd_type:
                    # Collect command lines until closing ```
                    pass

        # Flush last step
        if current_step_id > 0 and current_commands:
            for cmd_type, cmd in current_commands:
                steps.append(RunbookStep(
                    step_id=current_step_id,
                    title=current_title,
                    command_type=cmd_type,
                    command=cmd,
                    auto_executable=current_step_id in auto_steps,
                    approval_required=current_step_id in approval_steps,
                ))

        # Parse symptoms from ## Symptoms section
        symptoms = []
        in_symptoms = False
        for line in lines:
            if line.strip() == "## Symptoms":
                in_symptoms = True
                continue
            if in_symptoms:
                if line.startswith("## "):
                    break
                stripped = line.strip()
                if stripped.startswith("- "):
                    symptoms.append(stripped[2:])

        return Runbook(
            id=frontmatter.get("id", path.stem),
            name=frontmatter.get("name", path.stem),
            category=frontmatter.get("category", "general"),
            severity=frontmatter.get("severity", "medium"),
            clusters=frontmatter.get("clusters", []),
            symptoms=symptoms,
            steps=steps,
            raw_content=content,
        )

    def list_runbooks(self, category: Optional[str] = None) -> list[dict[str, Any]]:
        """List available runbooks, optionally filtered by category."""
        results = []
        for rb in self.runbooks.values():
            if category and rb.category != category:
                continue
            results.append({
                "id": rb.id,
                "name": rb.name,
                "category": rb.category,
                "severity": rb.severity,
                "clusters": rb.clusters,
                "step_count": len(rb.steps),
            })
        return results

    def get_runbook(self, runbook_id: str) -> Optional[dict[str, Any]]:
        """Get full runbook details by ID."""
        rb = self.runbooks.get(runbook_id)
        if not rb:
            return None
        return {
            "id": rb.id,
            "name": rb.name,
            "category": rb.category,
            "severity": rb.severity,
            "clusters": rb.clusters,
            "symptoms": rb.symptoms,
            "steps": [
                {
                    "step_id": s.step_id,
                    "title": s.title,
                    "command_type": s.command_type,
                    "command": s.command,
                    "auto_executable": s.auto_executable,
                    "approval_required": s.approval_required,
                }
                for s in rb.steps
            ],
            "raw_content": rb.raw_content,
        }

    def suggest_runbook(self, symptoms: str) -> list[dict[str, Any]]:
        """Find runbooks matching given symptoms using keyword matching.

        In production, this would use embedding-based semantic search.
        For now, uses simple keyword overlap scoring.
        """
        symptom_words = set(symptoms.lower().split())
        scored = []

        for rb in self.runbooks.values():
            score = 0
            for s in rb.symptoms:
                overlap = len(symptom_words & set(s.lower().split()))
                score += overlap
            # Also check name and category
            score += len(symptom_words & set(rb.name.lower().split()))
            score += len(symptom_words & set(rb.category.lower().split()))

            if score > 0:
                scored.append((score, rb))

        scored.sort(key=lambda x: x[0], reverse=True)
        return [
            {
                "id": rb.id,
                "name": rb.name,
                "category": rb.category,
                "severity": rb.severity,
                "match_score": score,
            }
            for score, rb in scored[:5]
        ]


# MCP Server definition
server = Server("runbook-mcp")
store = RunbookStore(RUNBOOK_DIR)


@server.list_tools()
async def list_tools() -> list[Tool]:
    """List available runbook tools."""
    return [
        Tool(
            name="list_runbooks",
            description="List all available runbooks, optionally filtered by category.",
            inputSchema={
                "type": "object",
                "properties": {
                    "category": {
                        "type": "string",
                        "description": "Filter by category (e.g., gpu-health, networking)",
                    },
                },
            },
        ),
        Tool(
            name="get_runbook",
            description="Get the full content of a runbook by ID.",
            inputSchema={
                "type": "object",
                "properties": {
                    "id": {"type": "string", "description": "Runbook ID"},
                },
                "required": ["id"],
            },
        ),
        Tool(
            name="suggest_runbook",
            description="Find runbooks that match the given symptoms description.",
            inputSchema={
                "type": "object",
                "properties": {
                    "symptoms": {
                        "type": "string",
                        "description": "Description of symptoms to match against runbooks",
                    },
                },
                "required": ["symptoms"],
            },
        ),
        Tool(
            name="execute_runbook_step",
            description=(
                "Execute a specific step of a runbook. "
                "Auto-executable steps run immediately. "
                "Approval-required steps return a pending status."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "runbook_id": {"type": "string", "description": "Runbook ID"},
                    "step_id": {"type": "integer", "description": "Step number to execute"},
                    "params": {
                        "type": "object",
                        "description": "Parameter substitutions for the step command",
                    },
                },
                "required": ["runbook_id", "step_id"],
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict[str, Any]) -> list[TextContent]:
    """Execute a runbook tool call."""
    try:
        if name == "list_runbooks":
            result = store.list_runbooks(category=arguments.get("category"))
            return [TextContent(type="text", text=str(result))]

        elif name == "get_runbook":
            result = store.get_runbook(arguments["id"])
            if result is None:
                return [TextContent(type="text", text=f"Runbook not found: {arguments['id']}")]
            return [TextContent(type="text", text=str(result))]

        elif name == "suggest_runbook":
            result = store.suggest_runbook(arguments["symptoms"])
            return [TextContent(type="text", text=str(result))]

        elif name == "execute_runbook_step":
            runbook_id = arguments["runbook_id"]
            step_id = arguments["step_id"]
            rb = store.runbooks.get(runbook_id)
            if not rb:
                return [TextContent(type="text", text=f"Runbook not found: {runbook_id}")]

            matching_steps = [s for s in rb.steps if s.step_id == step_id]
            if not matching_steps:
                return [TextContent(type="text", text=f"Step {step_id} not found in runbook {runbook_id}")]

            step = matching_steps[0]
            if step.approval_required:
                result = ExecutionResult(
                    runbook_id=runbook_id,
                    step_id=step_id,
                    status="pending_approval",
                    output=f"Step '{step.title}' requires human approval via Slack",
                )
                return [TextContent(type="text", text=str(result))]

            if step.auto_executable:
                # In production, this would execute the command
                result = ExecutionResult(
                    runbook_id=runbook_id,
                    step_id=step_id,
                    status="success",
                    output=f"[DRY RUN] Would execute: {step.command}",
                )
                return [TextContent(type="text", text=str(result))]

            return [TextContent(type="text", text=f"Step {step_id} is not marked as executable")]

        else:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]

    except Exception as e:
        logger.error("Tool call failed: %s — %s", name, str(e))
        return [TextContent(type="text", text=f"Error: {str(e)}")]


async def main():
    """Run the Runbook MCP server."""
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream)


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
