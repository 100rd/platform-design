"""GitOps Remediation Engine — pushes configurations via Pull Requests instead of direct writes."""

import logging
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)


class GitOpsRemediation:
    """Helper to perform SRE modifications via GitOps PR branches."""

    def __init__(self, repo_path: str) -> None:
        self.repo_path = Path(repo_path)

    def propose_change(
        self,
        file_path: str,
        target_content: str,
        replacement_content: str,
        branch_name: str,
        commit_message: str,
        create_pr: bool = False,
    ) -> str | None:
        """Creates a git branch, replaces file content, commits, and returns instructions/PR URL."""
        full_file_path = self.repo_path / file_path
        if not full_file_path.exists():
            logger.error("File %s does not exist in repo %s", file_path, self.repo_path)
            return None

        original_branch = None
        try:
            # Get the current branch so we can return to it later
            res = subprocess.run(
                ["git", "branch", "--show-current"],
                cwd=self.repo_path,
                capture_output=True,
                text=True,
                check=True,
            )
            original_branch = res.stdout.strip()
        except Exception as e:
            logger.warning("Failed to get current branch: %s", e)

        try:
            # 1. Checkout new branch (use -B to force reset if it already exists)
            logger.info("Checking out new/reset branch %s...", branch_name)
            subprocess.run(
                ["git", "checkout", "-B", branch_name],
                cwd=self.repo_path,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            # 2. Modify content
            content = full_file_path.read_text()
            if target_content not in content:
                logger.error("Target content to replace not found in %s", file_path)
                return None

            new_content = content.replace(target_content, replacement_content)
            full_file_path.write_text(new_content)

            # 3. Commit
            subprocess.run(["git", "add", file_path], cwd=self.repo_path, check=True)
            subprocess.run(
                ["git", "commit", "-m", commit_message],
                cwd=self.repo_path,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            logger.info("Successfully committed change to branch %s", branch_name)

            if create_pr:
                # 4. Push and create PR using gh CLI
                logger.info("Pushing branch %s to origin...", branch_name)
                subprocess.run(
                    ["git", "push", "-u", "origin", branch_name, "--force"],
                    cwd=self.repo_path,
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )

                logger.info("Creating pull request for branch %s...", branch_name)
                pr_res = subprocess.run(
                    [
                        "gh", "pr", "create",
                        "--title", commit_message,
                        "--body", (
                            f"Automated SRE GitOps remediation "
                            f"proposing change to `{file_path}`."
                        ),
                        "--head", branch_name,
                    ],
                    cwd=self.repo_path,
                    check=True,
                    capture_output=True,
                    text=True,
                )
                pr_url = pr_res.stdout.strip()
                logger.info("Successfully created pull request: %s", pr_url)
                return pr_url
            else:
                return (
                    f"Run: git push origin {branch_name} && "
                    f"gh pr create --title '{commit_message}' "
                    f"--body 'Automated SRE GitOps remediation'"
                )

        except Exception as e:
            logger.error("Failed to commit GitOps change: %s", e)
            if isinstance(e, subprocess.CalledProcessError):
                logger.error("Command: %s", e.cmd)
                if e.stdout:
                    logger.error("Stdout: %s", e.stdout)
                if e.stderr:
                    logger.error("Stderr: %s", e.stderr)
            return None
        finally:
            # Clean up branch checkout back to original branch
            if original_branch:
                logger.info("Restoring original branch %s...", original_branch)
                subprocess.run(
                    ["git", "checkout", original_branch],
                    cwd=self.repo_path,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    remediation = GitOpsRemediation(repo_path=".")
    # Exists for demonstration
