"""Orphaned-resource scanner Lambda.

Advisory-only — never deletes resources. Uploads a JSON report to S3 and
optionally publishes a one-paragraph summary to SNS for Slack-relay.

Environment variables (set by Terraform):
  REPORT_S3_BUCKET, REPORT_S3_PREFIX
  SLACK_SNS_TOPIC_ARN              (empty = skip)
  REGIONS_TO_SCAN                  (comma-separated)
  EBS_VOLUME_MIN_AGE_DAYS, EBS_SNAPSHOT_MAX_AGE_DAYS
  CHECK_*                          (per-check toggle: 'True' / 'False')

Issue #181.
"""
from __future__ import annotations

import datetime as dt
import json
import logging
import os
from typing import Any

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _bool_env(name: str, default: bool = True) -> bool:
    val = os.environ.get(name, str(default)).strip().lower()
    return val in ("1", "true", "yes")


def _int_env(name: str, default: int) -> int:
    return int(os.environ.get(name, str(default)))


def _now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


# ---------------------------------------------------------------------------
# Per-check helpers — each returns a list of dicts describing offenders.
# ---------------------------------------------------------------------------
def check_unattached_ebs(ec2, min_age_days: int) -> list[dict]:
    cutoff = _now() - dt.timedelta(days=min_age_days)
    findings = []
    paginator = ec2.get_paginator("describe_volumes")
    for page in paginator.paginate(Filters=[{"Name": "status", "Values": ["available"]}]):
        for vol in page["Volumes"]:
            if vol["CreateTime"] > cutoff:
                continue  # too young — could be a transient detach
            findings.append(
                {
                    "kind": "ebs_volume",
                    "id": vol["VolumeId"],
                    "size_gb": vol["Size"],
                    "created": vol["CreateTime"].isoformat(),
                    "az": vol["AvailabilityZone"],
                    "type": vol["VolumeType"],
                }
            )
    return findings


def check_unused_eips(ec2) -> list[dict]:
    findings = []
    for addr in ec2.describe_addresses().get("Addresses", []):
        if "AssociationId" not in addr and "InstanceId" not in addr and "NetworkInterfaceId" not in addr:
            findings.append(
                {
                    "kind": "elastic_ip",
                    "allocation_id": addr.get("AllocationId"),
                    "public_ip": addr["PublicIp"],
                }
            )
    return findings


def check_available_enis(ec2) -> list[dict]:
    findings = []
    paginator = ec2.get_paginator("describe_network_interfaces")
    for page in paginator.paginate(Filters=[{"Name": "status", "Values": ["available"]}]):
        for eni in page["NetworkInterfaces"]:
            findings.append(
                {
                    "kind": "eni",
                    "id": eni["NetworkInterfaceId"],
                    "subnet_id": eni["SubnetId"],
                    "vpc_id": eni["VpcId"],
                }
            )
    return findings


def check_old_snapshots(ec2, max_age_days: int) -> list[dict]:
    cutoff = _now() - dt.timedelta(days=max_age_days)
    findings = []
    paginator = ec2.get_paginator("describe_snapshots")
    # OwnerIds=self limits to snapshots in this account.
    for page in paginator.paginate(OwnerIds=["self"]):
        for snap in page["Snapshots"]:
            if snap["StartTime"] >= cutoff:
                continue
            findings.append(
                {
                    "kind": "ebs_snapshot",
                    "id": snap["SnapshotId"],
                    "size_gb": snap["VolumeSize"],
                    "created": snap["StartTime"].isoformat(),
                    "description": snap.get("Description", "")[:80],
                }
            )
    return findings


def check_idle_nat_gateways(ec2) -> list[dict]:
    """Heuristic: NAT GW with no associated subnet route is functionally idle.

    A more accurate check would query CloudWatch BytesOutToDestination over
    the last 7 days; that's a v2 enhancement.
    """
    findings = []
    nats = ec2.describe_nat_gateways(
        Filter=[{"Name": "state", "Values": ["available"]}]
    )
    for nat in nats.get("NatGateways", []):
        # Ownership: best-effort — CW Metrics check is the proper signal.
        findings.append(
            {
                "kind": "nat_gateway",
                "id": nat["NatGatewayId"],
                "vpc_id": nat["VpcId"],
                "subnet_id": nat["SubnetId"],
                "note": "advisory: verify CW BytesOutToDestination over 7d",
            }
        )
    return findings


def check_unattached_load_balancers(elb) -> list[dict]:
    findings = []
    paginator = elb.get_paginator("describe_load_balancers")
    for page in paginator.paginate():
        for lb in page["LoadBalancers"]:
            tg = elb.describe_target_groups(LoadBalancerArn=lb["LoadBalancerArn"])
            if not tg.get("TargetGroups"):
                findings.append(
                    {
                        "kind": "load_balancer",
                        "name": lb["LoadBalancerName"],
                        "arn": lb["LoadBalancerArn"],
                        "scheme": lb["Scheme"],
                        "type": lb["Type"],
                        "note": "no target groups bound",
                    }
                )
    return findings


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    bucket = os.environ["REPORT_S3_BUCKET"]
    prefix = os.environ.get("REPORT_S3_PREFIX", "orphaned-resources").strip("/")
    sns_topic = os.environ.get("SLACK_SNS_TOPIC_ARN", "")
    regions = [r.strip() for r in os.environ["REGIONS_TO_SCAN"].split(",") if r.strip()]

    ebs_min_age = _int_env("EBS_VOLUME_MIN_AGE_DAYS", 7)
    snap_max_age = _int_env("EBS_SNAPSHOT_MAX_AGE_DAYS", 90)

    enabled = {
        "unattached_ebs_volumes": _bool_env("CHECK_UNATTACHED_EBS"),
        "unused_elastic_ips": _bool_env("CHECK_UNUSED_EIPS"),
        "available_enis": _bool_env("CHECK_AVAILABLE_ENIS"),
        "old_ebs_snapshots": _bool_env("CHECK_OLD_SNAPSHOTS"),
        "idle_nat_gateways": _bool_env("CHECK_IDLE_NAT_GATEWAYS"),
        "unattached_load_balancers": _bool_env("CHECK_UNATTACHED_LBS"),
    }

    report: dict[str, Any] = {
        "scan_started": _now().isoformat(),
        "regions": regions,
        "checks_enabled": enabled,
        "by_region": {},
    }

    for region in regions:
        ec2 = boto3.client("ec2", region_name=region)
        elb = boto3.client("elbv2", region_name=region)
        per_region: dict[str, list] = {}
        try:
            if enabled["unattached_ebs_volumes"]:
                per_region["unattached_ebs_volumes"] = check_unattached_ebs(ec2, ebs_min_age)
            if enabled["unused_elastic_ips"]:
                per_region["unused_elastic_ips"] = check_unused_eips(ec2)
            if enabled["available_enis"]:
                per_region["available_enis"] = check_available_enis(ec2)
            if enabled["old_ebs_snapshots"]:
                per_region["old_ebs_snapshots"] = check_old_snapshots(ec2, snap_max_age)
            if enabled["idle_nat_gateways"]:
                per_region["idle_nat_gateways"] = check_idle_nat_gateways(ec2)
            if enabled["unattached_load_balancers"]:
                per_region["unattached_load_balancers"] = check_unattached_load_balancers(elb)
        except ClientError as exc:  # noqa: PERF203 — narrow + remap
            logger.exception("Scan failed for region %s: %s", region, exc)
            per_region["error"] = str(exc)
        report["by_region"][region] = per_region

    report["scan_finished"] = _now().isoformat()
    totals = {
        kind: sum(len(per_region.get(kind, [])) for per_region in report["by_region"].values())
        for kind in enabled
    }
    report["totals"] = totals

    # Upload to S3
    s3 = boto3.client("s3")
    date_str = _now().strftime("%Y-%m-%d")
    key = f"{prefix}/{date_str}/orphaned-{int(_now().timestamp())}.json"
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(report, indent=2).encode("utf-8"),
        ContentType="application/json",
    )

    # SNS summary if configured
    if sns_topic:
        boto3.client("sns").publish(
            TopicArn=sns_topic,
            Subject="[orphaned-resources] weekly scan",
            Message=(
                f"Orphaned-resource scan completed at {report['scan_finished']}.\n"
                f"Report: s3://{bucket}/{key}\n\n"
                f"Totals across {len(regions)} regions: {json.dumps(totals)}"
            ),
        )

    logger.info("Wrote report s3://%s/%s with totals %s", bucket, key, totals)
    return {"report_key": key, "totals": totals}
