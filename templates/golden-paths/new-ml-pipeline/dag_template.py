"""
{{DAG_NAME}} — Airflow DAG template (WS-F golden path, ADR-0041)

Mirrors the WS-B (ADR-0037) DAG shape:
  ingest_data -> run_batch_job -> register_results -> emit_drift_metrics

Instructions:
  1. Rename this file to apps/infra/airflow/dags/{{DAG_NAME}}.py
  2. Replace all SUBSTITUTE: comment blocks with real values.
  3. Implement the four # SCAFFOLD task bodies.
  4. See README.md for the MLflow and Pushgateway integration patterns.

Platform labels (ADR-0028):
  platform.system    = ml-pipeline
  platform.component = airflow
  platform.owner     = {{TEAM_OWNER}}
  platform.env       = {{PLATFORM_ENV}}
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow.decorators import dag, task
from airflow.models.param import Param

# ---------------------------------------------------------------------------
# Executor config — CPU task pods (adjust nodeSelector for your pool)
# ---------------------------------------------------------------------------
_CPU_EXECUTOR_CONFIG = {
    "pod_override": {
        "spec": {
            "nodeSelector": {"cloud.google.com/gke-nodepool": "ml-cpu-pool"},
        }
    }
}

# GPU executor config (uncomment if tasks need GPU resources)
# _GPU_EXECUTOR_CONFIG = {
#     "pod_override": {
#         "spec": {
#             "schedulerName": "volcano",
#             "nodeSelector": {
#                 "cloud.google.com/gke-nodepool": "gpu-a100-pool",
#                 "nvidia.com/gpu.present": "true",
#             },
#             "tolerations": [
#                 {"key": "nvidia.com/gpu", "operator": "Exists", "effect": "NoSchedule"}
#             ],
#         }
#     }
# }


@dag(
    # SUBSTITUTE: replace {{DAG_NAME}} with your snake_case DAG identifier.
    dag_id="{{DAG_NAME}}",
    # SUBSTITUTE: update the description.
    description="Custom ML pipeline: {{DAG_NAME}} (WS-F golden path).",
    # Set a schedule expression or leave None for triggered-only.
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    default_args={
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
        # SUBSTITUTE: replace {{TEAM_OWNER}} with your team slug.
        "owner": "{{TEAM_OWNER}}",
    },
    params={
        # SUBSTITUTE: replace {{TENANT}} default with your tenant identifier.
        "tenant": Param(default="{{TENANT}}", type="string", description="Tenant identifier"),
        # SUBSTITUTE: replace {{DOMAIN}} default with your ML domain.
        "domain": Param(
            default="{{DOMAIN}}",
            type="string",
            enum=["hft", "solana", "insurance", "rtb"],
            description="ML domain",
        ),
        "trigger_reason": Param(
            default="manual",
            type="string",
            enum=["threshold", "drift", "manual"],
            description="Trigger source",
        ),
    },
    tags=["ml-pipeline", "{{DAG_NAME}}"],
)
def dag_factory():
    """
    Custom ML pipeline: {{DAG_NAME}}.

    Replace this docstring with a description of what this pipeline does,
    what data it processes, and what model artifacts it produces.
    """

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def ingest_data(tenant: str, domain: str, **context) -> dict:
        """
        Load and validate the input data.
        Returns a data metadata dict (paths, row counts, snapshot IDs).

        SCAFFOLD: implement your data loading logic here.
        Examples:
          - Freeze an Iceberg snapshot (see train_domain_adapter.py pattern)
          - Download a GCS file: gs://<bucket>/<tenant>/<domain>/data.parquet
          - Query BigQuery with a time-bounded window
        """
        # SCAFFOLD: replace with real data ingestion
        run_ts = context["logical_date"].isoformat()
        return {
            "snapshot_id": f"scaffold-{tenant}-{domain}-{run_ts}",
            "row_count": 0,
            "source_path": f"gs://scaffold-bucket/{tenant}/{domain}/data.parquet",
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def run_batch_job(data_meta: dict, tenant: str, domain: str, **context) -> dict:
        """
        Execute the ML computation (training, scoring, or batch inference).
        Returns a results dict (metrics, output paths, job IDs).

        SCAFFOLD: implement your computation here.
        CPU tasks: use PythonOperator or BashOperator patterns.
        GPU tasks: submit a VolcanoJob (see train_domain_adapter.py for the pattern),
                   update executor_config to _GPU_EXECUTOR_CONFIG.
        """
        # SCAFFOLD: replace with real batch job submission
        return {
            "job_id": f"scaffold-{tenant}-{domain}",
            "status": "SCAFFOLD",
            "output_path": data_meta["source_path"].replace("data.parquet", "output.parquet"),
            "accuracy": 0.0,
            "loss": 0.0,
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def register_results(
        data_meta: dict,
        job_results: dict,
        tenant: str,
        domain: str,
        **context,
    ) -> dict:
        """
        Register metrics and artifacts in MLflow.
        Returns: {"mlflow_run_id": str, "model_version": str}

        Convention:
          experiment_name = f"{tenant}/{domain}/{{DAG_NAME}}"
          model_name      = "{{MODEL_NAME}}"

        SCAFFOLD: replace with real MLflow calls.
        """
        # SCAFFOLD: implement MLflow registration
        # import mlflow, os
        # mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
        # mlflow.set_experiment(f"{tenant}/{domain}/{{DAG_NAME}}")
        # with mlflow.start_run(run_name=f"{tenant}/{domain}"):
        #     mlflow.log_params({**data_meta, "tenant": tenant, "domain": domain})
        #     mlflow.log_metrics({"accuracy": job_results["accuracy"]})
        #     version = mlflow.register_model(
        #         f"runs:/{mlflow.active_run().info.run_id}/model",
        #         "{{MODEL_NAME}}")
        return {
            "mlflow_run_id": "scaffold-run-id",
            "model_version": "0",
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def emit_drift_metrics(
        job_results: dict,
        tenant: str,
        domain: str,
        **context,
    ) -> None:
        """
        Push feature distribution + accuracy metrics to the Prometheus Pushgateway
        so WS-C (ADR-0038) can compute drift and trigger retraining.

        Labels must match ADR-0038 D1: model_name, tenant, domain.
        Pushgateway: prometheus-pushgateway.ml-monitoring.svc.cluster.local:9091

        SCAFFOLD: replace with real metric values from job_results.
        """
        # SCAFFOLD: implement Pushgateway push
        # from prometheus_client import CollectorRegistry, Gauge, push_to_gateway
        # registry = CollectorRegistry()
        # accuracy_g = Gauge(
        #     "ml_monitoring_model_accuracy",
        #     "Model accuracy score",
        #     ["model_name", "tenant", "domain"],
        #     registry=registry,
        # )
        # drift_g = Gauge(
        #     "ml_monitoring_dataset_drift_score",
        #     "Dataset drift score",
        #     ["model_name", "tenant", "domain"],
        #     registry=registry,
        # )
        # accuracy_g.labels(
        #     model_name="{{MODEL_NAME}}", tenant=tenant, domain=domain
        # ).set(job_results["accuracy"])
        # drift_g.labels(
        #     model_name="{{MODEL_NAME}}", tenant=tenant, domain=domain
        # ).set(0.0)  # replace with real drift score
        # push_to_gateway(
        #     "prometheus-pushgateway.ml-monitoring.svc.cluster.local:9091",
        #     job="{{DAG_NAME}}",
        #     registry=registry,
        # )
        pass

    # -------------------------------------------------------------------------
    # DAG wiring
    # -------------------------------------------------------------------------
    tenant = "{{ params.tenant }}"
    domain = "{{ params.domain }}"

    data = ingest_data(tenant=tenant, domain=domain)
    results = run_batch_job(data_meta=data, tenant=tenant, domain=domain)
    reg = register_results(
        data_meta=data, job_results=results, tenant=tenant, domain=domain
    )
    emit_drift_metrics(job_results=results, tenant=tenant, domain=domain)

    # Uncomment to trigger downstream DAGs on success:
    # from airflow.operators.trigger_dagrun import TriggerDagRunOperator
    # trigger_downstream = TriggerDagRunOperator(
    #     task_id="trigger_downstream",
    #     trigger_dag_id="some_downstream_dag",
    #     conf={
    #         "mlflow_run_id": "{{ task_instance.xcom_pull('register_results')['mlflow_run_id'] }}",
    #     },
    # )
    # reg >> trigger_downstream  # type: ignore[operator]

    _ = reg  # suppress unused variable warning until trigger is wired


# SUBSTITUTE: rename the variable to match {{DAG_NAME}}_dag_instance
dag_instance = dag_factory()
