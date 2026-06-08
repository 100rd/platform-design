"""Placeholder Secrets Manager rotation Lambda handler.

This is a NON-FUNCTIONAL placeholder so the module can package and plan/validate
without a real rotation implementation. It implements the four-step rotation
protocol skeleton (createSecret, setSecret, testSecret, finishSecret) but does
NOT actually rotate any credential.

Before enabling rotation in a real environment, replace this with either:
  * one of the AWS-provided RDS rotation templates (single-user or
    alternating-user) — see
    https://docs.aws.amazon.com/secretsmanager/latest/userguide/reference_available-rotation-templates.html
  * a custom handler that calls the upstream provider's key-rotation API
    (for non-RDS credentials such as model-provider API keys),

and pass its packaged .zip via the module's `lambda_package_path` variable.

Rotation protocol reference:
  https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets-required-lambda-function.html
"""

import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_STEPS = ("createSecret", "setSecret", "testSecret", "finishSecret")


def lambda_handler(event, context):
    """Entry point invoked by Secrets Manager for each rotation step.

    `event` carries `SecretId`, `ClientRequestToken`, and `Step`.
    """
    arn = event.get("SecretId", "<unknown>")
    token = event.get("ClientRequestToken", "<unknown>")
    step = event.get("Step", "<unknown>")

    logger.info("rotation invoked: secret=%s token=%s step=%s", arn, token, step)

    if step not in _STEPS:
        raise ValueError(f"Invalid rotation step: {step!r}")

    # Placeholder: a real implementation performs the work for this `step`.
    # Raising here makes it obvious the placeholder must be replaced before
    # rotation is enabled against a live credential.
    raise NotImplementedError(
        "secret-rotation placeholder handler: replace with an AWS RDS rotation "
        "template or a custom rotator before enabling rotation. "
        f"(secret={arn}, step={step})"
    )
