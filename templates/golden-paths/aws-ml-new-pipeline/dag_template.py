"""
{{DAG_NAME}} -- Airflow DAG template (WS-F golden path, ADR-0041, AWS variant)

ADR gates: ADR-0041 (template approach), ADR-0048 (AWS backends)
GCP etalon: templates/golden-paths/new-ml-pipeline/dag_template.py

Mirrors the WS-B (ADR-0048 <- ADR-0037) DAG shape:
  ingest_data -> run_batch_job -> register_results -> emit_drift_metrics

AWS DELTAS vs GCP etalon:
  - ingest_data: reads from S3 (not GCS); Pod Identity = no static credentials (ADR-0018)
  - run_batch_job: nodeSelector uses karpenter.sh/nodepool (not cloud.google.com/gke-nodepool)
  - register_results: MLflow artifact store is s3:// (not gs://); MLFLOW_TRACKING_URI
    points to RDS-backed MLflow on EKS; AWS_DEFAULT_REGION set by Pod Identity SDK
  - emit_drift_metrics: Pushgateway address is identical (cluster-agnostic)

Instructions:
  1. Rename this file to apps/infra/airflow/dags/{{DAG_NAME}}.py
  2. Replace all SUBSTITUTE: comment blocks with real values.
  3. Implement the four # SCAFFOLD task bodies.
  4. See README.md for MLflow (S3/RDS), Pod Identity, and Pushgateway integration.

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
# Executor config -- CPU task pods on Graviton (non-GPU control workloads)
# ADR-0048 D1: Airflow control plane on non-GPU Graviton Karpenter pool (ADR-0046 D3)
# ---------------------------------------------------------------------------
_CPU_EXECUTOR_CONFIG = {
    "pod_override": {
        "spec": {
            # AWS Karpenter nodepool label (replaces cloud.google.com/gke-nodepool)
            "nodeSelector": {"karpenter.sh/nodepool": "graviton-cpu"},
        }
    }
}

# GPU executor config for GPU tasks (ADR-0044 D3 / Volcano gang scheduler)
# Uncomment and adjust the pool name to match your Karpenter NodePool (ADR-0046).
# _GPU_EXECUTOR_CONFIG = {
#     "pod_override": {
#         "spec": {
#             # Volcano gang scheduler required for EFA-fabric training jobs (ADR-0048 D1)
#             "schedulerName": "volcano",
#             # AWS EKS Karpenter GPU nodepool label (ADR-0046)
#             "nodeSelector": {
#                 "karpenter.sh/nodepool": "gpu-p4d-spot",  # adjust to your pool
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
    description="Custom AWS ML pipeline: {{DAG_NAME}} (WS-F golden path, ADR-0041).",
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
        # AWS-specific: region passed as a param so task logs include it.
        # SUBSTITUTE: replace {{AWS_REGION}} with your region.
        "aws_region": Param(
            default="{{AWS_REGION}}",
            type="string",
            description="AWS region for S3/ECR (must match the artifact bucket region)",
        ),
    },
    tags=["ml-pipeline", "{{DAG_NAME}}", "aws"],
)
def dag_factory():
    """
    Custom AWS ML pipeline: {{DAG_NAME}}.

    Replace this docstring with a description of what this pipeline does,
    what data it processes, and what model artifacts it produces.

    Artifact store: s3://{{S3_MLFLOW_ARTIFACTS_BUCKET}}/{{MODEL_NAME}}/{{TENANT}}/{{DOMAIN}}/
    Identity: EKS Pod Identity + ABAC (ADR-0018 + ADR-0048 D2) -- no static credentials.
    """

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def ingest_data(tenant: str, domain: str, aws_region: str, **context) -> dict:
        """
        Load and validate the input data.
        Returns a data metadata dict (paths, row counts, snapshot IDs).

        AWS: reads from S3 (not GCS). The task pod uses EKS Pod Identity --
        no static credentials needed (ADR-0018).

        SCAFFOLD: implement your data loading logic here.
        Examples:
          - Read an S3 Parquet snapshot:
              s3://<bucket>/<tenant>/<domain>/data.parquet
          - Read from DynamoDB or Kinesis
          - Freeze an Iceberg snapshot on S3
        """
        # SCAFFOLD: replace with real data ingestion
        import os  # noqa: PLC0415

        # AWS_DEFAULT_REGION is set by the Pod Identity SDK automatically.
        region = aws_region or os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
        run_ts = context["logical_date"].isoformat()
        return {
            "snapshot_id": f"scaffold-{tenant}-{domain}-{run_ts}",
            "row_count": 0,
            # SCAFFOLD: replace with real S3 path
            "source_path": f"s3://scaffold-bucket-{region}/{tenant}/{domain}/data.parquet",
            "aws_region": region,
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def run_batch_job(data_meta: dict, tenant: str, domain: str, **context) -> dict:
        """
        Execute the ML computation (training, scoring, or batch inference).
        Returns a results dict (metrics, output paths, job IDs).

        SCAFFOLD: implement your computation here.
        CPU tasks: use PythonOperator or BashOperator patterns.
        GPU tasks: submit a VolcanoJob (see train_domain_adapter.py for the pattern),
                   update executor_config to _GPU_EXECUTOR_CONFIG,
                   use karpenter.sh/nodepool (not cloud.google.com/gke-nodepool).
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

        AWS convention:
          experiment_name = f"{tenant}/{domain}/{{DAG_NAME}}"
          model_name      = "{{MODEL_NAME}}"
          artifacts stored at:
            s3://{{S3_MLFLOW_ARTIFACTS_BUCKET}}/{{MODEL_NAME}}/{tenant}/{domain}/

        Identity: MLFLOW_TRACKING_URI from ESO ExternalSecret (AWS Secrets Manager).
        S3 write: EKS Pod Identity bound to the aws-ml-artifact-store IAM role
                  (ADR-0018 + ADR-0048 D2). AWS_DEFAULT_REGION set automatically.

        SCAFFOLD: replace with real MLflow calls.
        """
        # SCAFFOLD: implement MLflow registration
        # import mlflow, os
        # mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
        # mlflow.set_experiment(f"{tenant}/{domain}/{{DAG_NAME}}")
        # with mlflow.start_run(run_name=f"{tenant}/{domain}"):
        #     mlflow.log_params({**data_meta, "tenant": tenant, "domain": domain})
        #     mlflow.log_metrics({"accuracy": job_results["accuracy"]})
        #     # mlflow.pytorch.log_model(model, "model")  # writes to S3 via Pod Identity
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
        so WS-C (ADR-0048 D4 <- ADR-0038) can compute drift and trigger retraining.

        Labels must match ADR-0038 D1: model_name, tenant, domain.
        Pushgateway: prometheus-pushgateway.ml-monitoring.svc.cluster.local:9091
        (Cluster-agnostic -- identical to the GCP etalon.)

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
    aws_region = "{{ params.aws_region }}"

    data = ingest_data(tenant=tenant, domain=domain, aws_region=aws_region)
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
