"""Secret detection in agent outputs.

Scans agent responses before they are sent to Slack to prevent
accidental secret leakage. Patterns are designed to catch common
secret formats without being overly aggressive.
"""

import logging
import re
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class ScanResult:
    """Result of a secret scan."""

    contains_secrets: bool
    redacted_text: str
    findings: list[str]


# Regex patterns for common secret formats
SECRET_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("AWS Access Key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("AWS Secret Key", re.compile(r"(?i)aws_secret_access_key\s*[=:]\s*\S+")),
    ("Generic API Key", re.compile(r"(?i)(api[_-]?key|apikey)\s*[=:]\s*['\"]?\S{20,}['\"]?")),
    ("Bearer Token", re.compile(r"Bearer\s+[A-Za-z0-9\-._~+/]+=*")),
    ("Basic Auth", re.compile(r"Basic\s+[A-Za-z0-9+/]+=*")),
    ("Private Key", re.compile(r"-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----")),
    ("Generic Secret", re.compile(r"(?i)(password|passwd|secret)\s*[=:]\s*['\"]?\S+['\"]?")),
    ("Slack Token", re.compile(r"xox[baprs]-[0-9a-zA-Z\-]+")),
    ("GitHub Token", re.compile(r"gh[pous]_[A-Za-z0-9_]{36,}")),
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+")),
]

REDACTION_PLACEHOLDER = "***REDACTED***"


def scan_text(text: str) -> ScanResult:
    """Scan text for secret patterns and return redacted version.

    Returns a ScanResult with:
    - contains_secrets: True if any secrets were found
    - redacted_text: Text with secrets replaced by ***REDACTED***
    - findings: List of detected secret types
    """
    findings: list[str] = []
    redacted = text

    for name, pattern in SECRET_PATTERNS:
        matches = pattern.findall(redacted)
        if matches:
            findings.append(f"{name} ({len(matches)} occurrence(s))")
            redacted = pattern.sub(REDACTION_PLACEHOLDER, redacted)

    if findings:
        logger.warning(
            "secrets_detected_in_output",
            finding_count=len(findings),
            findings=findings,
        )

    return ScanResult(
        contains_secrets=bool(findings),
        redacted_text=redacted,
        findings=findings,
    )


def sanitize_agent_output(text: str) -> str:
    """Sanitize agent output by redacting any detected secrets.

    This is applied as a post-processing step before sending
    agent responses to Slack or storing in logs.
    """
    result = scan_text(text)
    return result.redacted_text
