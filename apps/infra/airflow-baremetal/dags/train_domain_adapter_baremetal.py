"""
train_domain_adapter_baremetal — Airflow DAG (WS-B, ADR-0037 reused)

Bare-metal variant of the four-DAG training pipeline
(docs/transaction-analytics/04-training-pipeline.md):
  train_domain_adapter -> eval_adapter_debate -> mine_templates -> promote_to_edge

Key differences vs the GKE DAG:
- KubernetesExecutor task pods submit to the *Volcano* scheduler
  (executor_config: schedulerName=volcano, queue=training-default)
  using the UK DC Volcano queue taxonomy from 06-uk-datacenters.md.
- GPU tolerations set on training task pods
  (nvidia.com/gpu:NoSchedule => Exists).
- Artifact store: MinIO / Ceph-RGW S3 endpoint
  (MLFLOW_S3_ENDPOINT_URL injected from mlflow-s3-credentials Secret).
- No GCP Workload Identity; credentials from Vault/ESO (ADR-0049).

ADR-0028: platform.system = ml-pipeline, platform.component = airflow.
ADR-0037: reused orchestrator design; only substrate changes (bare metal).
ADR-0049: UK-isolated control plane.
ADR-0052: S3 artifact store = MinIO (default) or Ceph-RGW.
"""

from __future__ import annotations

import os
from datetime import timedelta

from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator
from airflow.utils.dates import days_ago
from kubernetes.client import (
    V1Toleration,
    V1ResourceRequirements,
)

# ---------------------------------------------------------------------------
# Volcano queue taxonomy (UK DC, 06-uk-datacenters.md)
# H100 pool queues: training-default | training-bootstrap | training-urgent
# ---------------------------------------------------------------------------
VOLCANO_QUEUE = os.getenv("VOLCANO_TRAINING_QUEUE", "training-default")

# ---------------------------------------------------------------------------
# Shared executor_config: submit GPU task pods to Volcano scheduler.
# ---------------------------------------------------------------------------
GPU_EXECUTOR_CONFIG = {
    "pod_override": {
        "spec": {
            # Route via Volcano secondary scheduler (ADR-0037 + UK DC WS-A).
            "schedulerName": "volcano",
            "tolerations": [
                V1Toleration(
                    key="nvidia.com/gpu",
                    operator="Exists",
                    effect="NoSchedule",
                )
            ],
        }
    }
}

# ---------------------------------------------------------------------------
# Shared resource requirements for training pods
# ---------------------------------------------------------------------------
TRAINING_RESOURCES = V1ResourceRequirements(
    requests={"cpu": "4", "memory": "16Gi", "nvidia.com/gpu": "1"},
    limits={"cpu": "8", "memory": "32Gi", "nvidia.com/gpu": "1"},
)

DEFAULT_ARGS = {
    "owner": "team-ml",
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
    "labels": {
        # ADR-0028 labels on task pods
        "platform.system": "ml-pipeline",
        "platform.component": "airflow",
        "platform.managed-by": "argocd",
    },
}

with DAG(
    dag_id="train_domain_adapter_baremetal",
    description=(
        "Bare-metal: train_domain_adapter -> eval_adapter_debate -> "
        "mine_templates -> promote_to_edge. Volcano GPU queues. ADR-0037/0049/0052."
    ),
    default_args=DEFAULT_ARGS,
    schedule_interval=None,  # Triggered by GH Actions ml-pipeline-baremetal.yml
    start_date=days_ago(1),
    catchup=False,
    tags=["ml-pipeline", "bare-metal", "gpu", "adr-0037", "adr-0052"],
    params={
        "model_id": "fraud-uk",
        # S3 artifact URI prefix (MinIO/Ceph-RGW; overridden per-run by GH Actions).
        "artifact_uri": "s3://mlflow-artifacts",
    },
) as dag:

    # -----------------------------------------------------------------------
    # Task 1: train_domain_adapter
    # Runs the adapter training job on the H100 GPU pool via Volcano.
    # -----------------------------------------------------------------------
    train = KubernetesPodOperator(
        task_id="train_domain_adapter",
        name="train-domain-adapter",
        namespace="ml-pipeline",
        image="{{ var.value.TRAINING_IMAGE | default('training-runner:latest') }}",
        cmds=["python", "-m", "training.train_domain_adapter"],
        env_vars={
            "MODEL_ID": "{{ params.model_id }}",
            "ARTIFACT_URI": "{{ params.artifact_uri }}",
            # MLFLOW_TRACKING_URI + S3 credentials injected from mlflow-tracking-uri
            # and mlflow-s3-credentials Secrets (via Airflow extraEnv in values.yaml).
        },
        container_resources=TRAINING_RESOURCES,
        executor_config=GPU_EXECUTOR_CONFIG,
        annotations={
            # Volcano queue annotation (secondary scheduler picks this up)
            "scheduling.volcano.sh/queue-name": VOLCANO_QUEUE,
        },
        is_delete_operator_pod=True,
        get_logs=True,
    )

    # -----------------------------------------------------------------------
    # Task 2: eval_adapter_debate
    # Quality gate: runs evaluation; must pass before registration.
    # -----------------------------------------------------------------------
    eval_gate = KubernetesPodOperator(
        task_id="eval_adapter_debate",
        name="eval-adapter-debate",
        namespace="ml-pipeline",
        image="{{ var.value.EVAL_IMAGE | default('eval-runner:latest') }}",
        cmds=["python", "-m", "evaluation.eval_adapter_debate"],
        env_vars={
            "MODEL_ID": "{{ params.model_id }}",
            "ARTIFACT_URI": "{{ params.artifact_uri }}",
        },
        container_resources=V1ResourceRequirements(
            requests={"cpu": "2", "memory": "8Gi"},
            limits={"cpu": "4", "memory": "16Gi"},
        ),
        # Eval may run on CPU pool (no GPU toleration needed for debate eval).
        executor_config={},
        is_delete_operator_pod=True,
        get_logs=True,
    )

    # -----------------------------------------------------------------------
    # Task 3: mine_templates
    # Template mining runs after successful eval.
    # -----------------------------------------------------------------------
    mine = KubernetesPodOperator(
        task_id="mine_templates",
        name="mine-templates",
        namespace="ml-pipeline",
        image="{{ var.value.MINING_IMAGE | default('mining-runner:latest') }}",
        cmds=["python", "-m", "mining.mine_templates"],
        env_vars={
            "MODEL_ID": "{{ params.model_id }}",
            "ARTIFACT_URI": "{{ params.artifact_uri }}",
        },
        container_resources=V1ResourceRequirements(
            requests={"cpu": "2", "memory": "8Gi"},
            limits={"cpu": "4", "memory": "16Gi"},
        ),
        executor_config={},
        is_delete_operator_pod=True,
        get_logs=True,
    )

    # -----------------------------------------------------------------------
    # Task 4: promote_to_edge
    # Triggers Kargo promotion (bare-metal serving => edge fleet).
    # -----------------------------------------------------------------------
    promote = KubernetesPodOperator(
        task_id="promote_to_edge",
        name="promote-to-edge",
        namespace="ml-pipeline",
        image="{{ var.value.KARGO_CLI_IMAGE | default('kargo-cli:latest') }}",
        cmds=["kargo", "promote"],
        arguments=[
            "--project", "ml-pipeline-baremetal",
            "--freight", "{{ params.model_id }}-{{ run_id }}",
            "--stage", "staging",
        ],
        executor_config={},
        is_delete_operator_pod=True,
        get_logs=True,
    )

    # Pipeline: train -> eval -> mine -> promote
    train >> eval_gate >> mine >> promote
