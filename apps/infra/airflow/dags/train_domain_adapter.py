"""
train_domain_adapter — DAG scaffold (ADR-0037 / WS-B)

Triggered when a retraining condition is met (threshold, drift, or manual).
See docs/transaction-analytics/04-training-pipeline.md for the full design.

DAG steps:
  1. freeze_snapshot   — freeze the Iceberg training snapshot (versioned)
  2. launch_training   — submit a Volcano gang job for DeepSpeed ZeRO-3 SFT+LoRA
                         on the 8x H100 GPU pool
  3. poll_training     — wait for the Volcano job to reach terminal state
  4. register_adapter  — write adapter metadata + Iceberg path to MLflow + Postgres
  5. trigger_eval      — fire eval_adapter_debate DAG

All GPU tasks: the Airflow task pod itself is CPU-only (KubernetesExecutor
default); it submits the VolcanoJob via the Kubernetes API and polls status.

Platform labels (ADR-0028):
  platform.system   = ml-pipeline
  platform.component = airflow
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow.decorators import dag, task
from airflow.models.param import Param
from airflow.operators.trigger_dagrun import TriggerDagRunOperator

# ---------------------------------------------------------------------------
# Default pod executor config — CPU task pods only
# ---------------------------------------------------------------------------
_CPU_EXECUTOR_CONFIG = {
    "pod_override": {
        "spec": {
            "nodeSelector": {"cloud.google.com/gke-nodepool": "ml-cpu-pool"},
        }
    }
}


@dag(
    dag_id="train_domain_adapter",
    description="SFT + LoRA training on Qwen 2.5 3B via DeepSpeed ZeRO-3 (8x H100).",
    schedule=None,  # triggered only; not time-scheduled
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    default_args={
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
        "owner": "team-ml",
    },
    params={
        "tenant": Param(default="default", type="string", description="Tenant identifier"),
        "domain": Param(
            default="hft",
            type="string",
            enum=["hft", "solana", "insurance", "rtb"],
            description="ML domain to train",
        ),
        "trigger_reason": Param(
            default="threshold",
            type="string",
            enum=["threshold", "drift", "manual"],
            description="Retraining trigger source",
        ),
    },
    tags=["ml-pipeline", "training"],
)
def train_domain_adapter():
    """
    Train a LoRA domain adapter for a given (tenant, domain) pair.
    On success, triggers eval_adapter_debate.
    """

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def freeze_snapshot(tenant: str, domain: str, **context) -> dict:
        """
        Freeze the Iceberg training snapshot and record snapshot_id in Postgres runs.
        Returns snapshot metadata for downstream tasks.

        Reproducibility invariant: every training run records the exact Iceberg
        snapshot version so training data can be reconstructed for SOC2 audit.
        See docs/transaction-analytics/04-training-pipeline.md.
        """
        # SCAFFOLD: implement Iceberg client call to freeze snapshot
        # from pyiceberg.catalog import load_catalog
        # catalog = load_catalog("gcp_catalog", **catalog_config)
        # table = catalog.load_table(f"labels.{domain}.outcome")
        # snapshot_id = table.current_snapshot().snapshot_id
        run_ts = context["logical_date"].isoformat()
        return {
            "snapshot_id": f"scaffold-{tenant}-{domain}-{run_ts}",
            "snapshot_version": 0,
            "train_rows": 0,
            "eval_rows": 0,
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def launch_training(snapshot_meta: dict, tenant: str, domain: str, **context) -> str:
        """
        Submit a VolcanoJob (gang job, minMember=8 for 8x H100) via the Kubernetes
        client. The job container runs the DeepSpeed SFT training script.
        Returns the VolcanoJob name for polling.

        Training config: training/configs/{domain}.yaml
        LR=1e-4, cosine decay, 3% warmup, rank-16 LoRA.
        """
        # SCAFFOLD: build and submit VolcanoJob manifest via kubernetes client
        # from kubernetes import client as k8s_client, config as kube_config
        # kube_config.load_incluster_config()
        # custom_api = k8s_client.CustomObjectsApi()
        # volcano_job = _build_volcano_job_manifest(tenant, domain, snapshot_meta)
        # custom_api.create_namespaced_custom_object(
        #     group="batch.volcano.sh", version="v1alpha1",
        #     namespace="ml-pipeline", plural="jobs", body=volcano_job)
        run_id = context.get("run_id", "scaffold")
        return f"train-{tenant}-{domain}-{run_id}"

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def poll_training(job_name: str) -> dict:
        """
        Poll VolcanoJob status until Completed/Failed/Aborted.
        Returns training metrics dict (loss, eval_perplexity, wall_time_s, gpu_hours).
        """
        # SCAFFOLD: poll custom object status with exponential backoff
        # while job.status.state.phase not in ("Completed", "Failed", "Aborted"):
        #     time.sleep(30)
        return {
            "job_name": job_name,
            "status": "SCAFFOLD",
            "eval_perplexity": 0.0,
            "wall_time_s": 0,
            "gpu_hours": 0.0,
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def register_adapter(
        snapshot_meta: dict,
        training_result: dict,
        tenant: str,
        domain: str,
        **context,
    ) -> dict:
        """
        Register the trained adapter in MLflow Model Registry and Postgres runs table.
        Returns adapter_id and mlflow_run_id for downstream DAGs.

        MLflow tracking URI available as MLFLOW_TRACKING_URI env var
        (injected from ExternalSecret mlflow-tracking-uri in values.yaml).
        """
        # SCAFFOLD: mlflow.start_run(), log params/metrics, mlflow.register_model()
        # import mlflow
        # with mlflow.start_run(run_name=f"{tenant}/{domain}"):
        #     mlflow.log_params({**snapshot_meta, "tenant": tenant, "domain": domain})
        #     mlflow.log_metrics({"eval_perplexity": training_result["eval_perplexity"],
        #                         "gpu_hours": training_result["gpu_hours"]})
        #     mlflow.pytorch.log_model(adapter, "adapter")
        #     model_version = mlflow.register_model(
        #         f"runs:/{mlflow.active_run().info.run_id}/adapter",
        #         f"{tenant}.{domain}.adapter")
        return {
            "adapter_id": f"scaffold-{tenant}-{domain}",
            "mlflow_run_id": "scaffold-mlflow-run-id",
        }

    # -------------------------------------------------------------------------
    # DAG wiring
    # -------------------------------------------------------------------------
    tenant = "{{ params.tenant }}"
    domain = "{{ params.domain }}"

    snap = freeze_snapshot(tenant=tenant, domain=domain)
    job_name = launch_training(snapshot_meta=snap, tenant=tenant, domain=domain)
    result = poll_training(job_name=job_name)
    adapter_meta = register_adapter(
        snapshot_meta=snap,
        training_result=result,
        tenant=tenant,
        domain=domain,
    )

    # Trigger eval DAG on success
    trigger_eval = TriggerDagRunOperator(
        task_id="trigger_eval_adapter_debate",
        trigger_dag_id="eval_adapter_debate",
        conf={
            "tenant": tenant,
            "domain": domain,
            "adapter_id": "{{ task_instance.xcom_pull('register_adapter')['adapter_id'] }}",
            "mlflow_run_id": "{{ task_instance.xcom_pull('register_adapter')['mlflow_run_id'] }}",
        },
        wait_for_completion=False,
    )

    adapter_meta >> trigger_eval  # type: ignore[operator]


train_domain_adapter_dag = train_domain_adapter()
