"""Runbook Automation Agent — executes pre-approved runbook steps with audit logging."""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are a Runbook Automation specialist for a multi-cluster Kubernetes platform.

Your capabilities:
- Execute pre-approved runbook steps automatically
- Request human approval for privileged operations via Slack
- Log all runbook executions for audit compliance
- Suggest runbook improvements based on execution patterns
- Chain multiple runbook steps for complex remediation

Execution model:
- Auto-executable steps: diagnostics, read-only queries, status checks
- Approval-required steps: node cordoning, pod deletion, config changes
- Never execute destructive operations without explicit approval
- Always log execution results to ClickHouse audit table

Safety rules:
1. Never skip approval for approval-required steps
2. Always verify preconditions before execution
3. Stop execution chain on any step failure
4. Include rollback information in every execution log
5. Rate limit: max 10 runbook executions per incident
"""


@dataclass
class RunbookExecution:
    """Record of a runbook step execution."""

    execution_id: str
    runbook_id: str
    step_id: int
    step_title: str
    status: str  # pending, approved, executing, success, failed, skipped
    command: str = ""
    output: str = ""
    approved_by: Optional[str] = None
    executed_at: Optional[str] = None
    duration_seconds: float = 0
    error: Optional[str] = None


@dataclass
class RunbookSession:
    """An active runbook execution session."""

    session_id: str
    runbook_id: str
    runbook_name: str
    incident_id: Optional[str] = None
    cluster: str = ""
    triggered_by: str = ""
    executions: list[RunbookExecution] = field(default_factory=list)
    status: str = "in_progress"  # in_progress, completed, failed, aborted
    started_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    completed_at: Optional[str] = None


class RunbookAutomationAgent:
    """Runbook Automation Agent — executes operational procedures with safety controls."""

    def __init__(self) -> None:
        self.active_sessions: dict[str, RunbookSession] = {}
        self.execution_count_per_incident: dict[str, int] = {}
        self.max_executions_per_incident = 10

    async def start_runbook(
        self,
        runbook_id: str,
        runbook_name: str,
        cluster: str,
        incident_id: Optional[str] = None,
        triggered_by: str = "agent",
    ) -> RunbookSession:
        """Start a runbook execution session."""
        session_id = f"rb-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}"

        # Rate limiting per incident
        if incident_id:
            count = self.execution_count_per_incident.get(incident_id, 0)
            if count >= self.max_executions_per_incident:
                logger.warning(
                    "Rate limit: %d executions for incident %s",
                    count,
                    incident_id,
                )
                session = RunbookSession(
                    session_id=session_id,
                    runbook_id=runbook_id,
                    runbook_name=runbook_name,
                    incident_id=incident_id,
                    cluster=cluster,
                    triggered_by=triggered_by,
                    status="aborted",
                )
                return session

        session = RunbookSession(
            session_id=session_id,
            runbook_id=runbook_id,
            runbook_name=runbook_name,
            incident_id=incident_id,
            cluster=cluster,
            triggered_by=triggered_by,
        )

        self.active_sessions[session_id] = session
        logger.info("Started runbook session %s: %s", session_id, runbook_name)
        return session

    async def execute_step(
        self,
        session_id: str,
        step_id: int,
        step_title: str,
        command: str,
        auto_executable: bool,
        params: Optional[dict[str, str]] = None,
    ) -> RunbookExecution:
        """Execute a single runbook step.

        Auto-executable steps run immediately.
        Approval-required steps return pending status.
        """
        session = self.active_sessions.get(session_id)
        if not session:
            return RunbookExecution(
                execution_id="error",
                runbook_id="unknown",
                step_id=step_id,
                step_title=step_title,
                status="failed",
                error="Session not found",
            )

        # Apply parameter substitutions
        resolved_command = command
        if params:
            for key, value in params.items():
                resolved_command = resolved_command.replace(f"{{{key}}}", value)

        execution = RunbookExecution(
            execution_id=f"{session_id}-step-{step_id}",
            runbook_id=session.runbook_id,
            step_id=step_id,
            step_title=step_title,
            command=resolved_command,
        )

        if not auto_executable:
            execution.status = "pending"
            logger.info(
                "Step %d requires approval: %s",
                step_id,
                step_title,
            )
        else:
            # In production, execute the command
            execution.status = "success"
            execution.output = f"[DRY RUN] Would execute: {resolved_command}"
            execution.executed_at = datetime.now(timezone.utc).isoformat()
            logger.info(
                "Executed step %d: %s (auto)",
                step_id,
                step_title,
            )

        session.executions.append(execution)

        # Track execution count
        if session.incident_id:
            self.execution_count_per_incident[session.incident_id] = (
                self.execution_count_per_incident.get(session.incident_id, 0) + 1
            )

        return execution

    async def approve_step(
        self,
        session_id: str,
        step_id: int,
        approved_by: str,
    ) -> RunbookExecution:
        """Approve and execute a pending step."""
        session = self.active_sessions.get(session_id)
        if not session:
            return RunbookExecution(
                execution_id="error",
                runbook_id="unknown",
                step_id=step_id,
                step_title="unknown",
                status="failed",
                error="Session not found",
            )

        for execution in session.executions:
            if execution.step_id == step_id and execution.status == "pending":
                execution.approved_by = approved_by
                execution.status = "success"
                execution.executed_at = datetime.now(timezone.utc).isoformat()
                execution.output = (
                    f"[DRY RUN] Approved by {approved_by}, "
                    f"would execute: {execution.command}"
                )
                logger.info(
                    "Step %d approved by %s and executed",
                    step_id,
                    approved_by,
                )
                return execution

        return RunbookExecution(
            execution_id="error",
            runbook_id=session.runbook_id,
            step_id=step_id,
            step_title="unknown",
            status="failed",
            error=f"No pending step {step_id} found",
        )

    def get_session_summary(self, session_id: str) -> Optional[dict[str, Any]]:
        """Get summary of a runbook execution session."""
        session = self.active_sessions.get(session_id)
        if not session:
            return None

        return {
            "session_id": session.session_id,
            "runbook": session.runbook_name,
            "cluster": session.cluster,
            "status": session.status,
            "steps_total": len(session.executions),
            "steps_completed": sum(
                1 for e in session.executions if e.status == "success"
            ),
            "steps_pending": sum(
                1 for e in session.executions if e.status == "pending"
            ),
            "steps_failed": sum(
                1 for e in session.executions if e.status == "failed"
            ),
        }
