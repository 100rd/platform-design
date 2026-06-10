"""
mine_templates — DAG scaffold (ADR-0037 / WS-B)

Triggered by eval_adapter_debate on gate pass.
Batch template mining over the same training window as the adapter.
See docs/transaction-analytics/04-training-pipeline.md for domain strategies.

DAG steps:
  1. load_training_window  — fetch the same Iceberg window used for training
                             plus the adapter's own predictions on that window
  2. mine_domain_templates — run domain-specific mining strategy
  3. content_hash_bundle   — content-hash the bundle for deterministic ID
  4. register_bundle       — store bundle in Iceberg + Postgres + MLflow run
  5. trigger_promote       — fire promote_to_edge DAG

Platform labels (ADR-0028): platform.system = ml-pipeline
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow.decorators import dag, task
from airflow.models.param import Param
from airflow.operators.trigger_dagrun import TriggerDagRunOperator

_CPU_EXECUTOR_CONFIG = {
    "pod_override": {
        "spec": {
            "nodeSelector": {"cloud.google.com/gke-nodepool": "ml-cpu-pool"},
        }
    }
}

_GPU_MINE_EXECUTOR_CONFIG = {
    "pod_override": {
        "spec": {
            "schedulerName": "volcano",
            "nodeSelector": {
                "cloud.google.com/gke-nodepool": "gpu-a100-pool",
                "nvidia.com/gpu.present": "true",
            },
            "tolerations": [
                {
                    "key": "nvidia.com/gpu",
                    "operator": "Exists",
                    "effect": "NoSchedule",
                }
            ],
        }
    }
}


@dag(
    dag_id="mine_templates",
    description="Batch template mining over the adapter training window.",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=5,
    default_args={
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
        "owner": "team-ml",
    },
    params={
        "tenant": Param(default="default", type="string"),
        "domain": Param(
            default="hft",
            type="string",
            enum=["hft", "solana", "insurance", "rtb"],
        ),
        "adapter_id": Param(default="", type="string"),
        "mlflow_run_id": Param(default="", type="string"),
    },
    tags=["ml-pipeline", "templates"],
)
def mine_templates():
    """
    Mine templates from the adapter's training window.
    Adapters and templates are versioned together — never mixed across windows.
    """

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def load_training_window(tenant: str, domain: str, adapter_id: str) -> dict:
        """
        Fetch the same Iceberg training window used for the adapter.
        Also loads adapter predictions on that window (mine from what the model
        does, not only from what happened).
        """
        # SCAFFOLD: look up adapter training snapshot from Postgres runs table,
        # load corresponding Iceberg snapshot
        return {
            "window_table": f"scaffold_training_{domain}",
            "window_rows": 0,
            "adapter_predictions_ref": f"scaffold_predictions_{adapter_id}",
        }

    @task(executor_config=_GPU_MINE_EXECUTOR_CONFIG)
    def mine_domain_templates(window_ref: dict, tenant: str, domain: str) -> dict:
        """
        Run domain-specific mining strategy:
          - HFT: PrefixSpan sequence mining + embedding clustering (50-200 patterns)
          - Solana: DAG mining on program-call graphs + Qdrant similarity clusters
          - Insurance: schema heuristics + LLM pass + expert-feedback rules
          - RTB: XGBoost surrogate decision-tree + audience-segment vectors
        Output: JSON rules + numeric vectors + NL descriptions per domain.
        """
        # SCAFFOLD: implement per-domain mining strategy
        return {
            "template_count": 0,
            "template_refs": [],
            "mining_strategy": domain,
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def content_hash_bundle(template_result: dict, tenant: str, domain: str) -> str:
        """
        Content-hash the template bundle to produce a deterministic bundle_id.
        Edge agent records which bundle it runs and reports via heartbeat topic.
        """
        import hashlib
        import json

        content = json.dumps(template_result, sort_keys=True)
        return hashlib.sha256(content.encode()).hexdigest()[:16]

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def register_bundle(
        template_result: dict,
        bundle_id: str,
        adapter_id: str,
        mlflow_run_id: str,
        tenant: str,
        domain: str,
    ) -> dict:
        """
        Store bundle in Iceberg _platform.templates.{domain}.{bundle_id},
        record in Postgres, and log artifact to MLflow run.
        """
        # SCAFFOLD: write to Iceberg + mlflow.log_artifact(bundle_path)
        return {
            "bundle_id": bundle_id,
            "bundle_table": f"scaffold_templates_{domain}_{bundle_id}",
        }

    # -------------------------------------------------------------------------
    # DAG wiring
    # -------------------------------------------------------------------------
    tenant = "{{ params.tenant }}"
    domain = "{{ params.domain }}"
    adapter_id = "{{ params.adapter_id }}"
    mlflow_run_id = "{{ params.mlflow_run_id }}"

    window_ref = load_training_window(tenant=tenant, domain=domain, adapter_id=adapter_id)
    template_result = mine_domain_templates(
        window_ref=window_ref,
        tenant=tenant,
        domain=domain,
    )
    bundle_hash = content_hash_bundle(
        template_result=template_result,
        tenant=tenant,
        domain=domain,
    )
    bundle_meta = register_bundle(
        template_result=template_result,
        bundle_id=bundle_hash,
        adapter_id=adapter_id,
        mlflow_run_id=mlflow_run_id,
        tenant=tenant,
        domain=domain,
    )

    trigger_promote = TriggerDagRunOperator(
        task_id="trigger_promote_to_edge",
        trigger_dag_id="promote_to_edge",
        conf={
            "tenant": tenant,
            "domain": domain,
            "adapter_id": adapter_id,
            "bundle_id": "{{ task_instance.xcom_pull('register_bundle')['bundle_id'] }}",
            "mlflow_run_id": mlflow_run_id,
        },
        wait_for_completion=False,
    )

    bundle_meta >> trigger_promote  # type: ignore[operator]


mine_templates_dag = mine_templates()
