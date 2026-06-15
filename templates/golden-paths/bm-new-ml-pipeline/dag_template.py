"""
{{DAG_NAME}} -- Airflow DAG template (WS-F BM golden path, ADR-0041)

Substrate: bare-metal Talos UK DC cluster (ADR-0049).
Mirrors the WS-B (ADR-0037) DAG shape re-targeted at MinIO/Ceph-RGW + VolcanoJobs.

Key differences from the GCP DAG template (templates/golden-paths/new-ml-pipeline/):
  - GPU work submitted as VolcanoJob on UK DC queue taxonomy (ADR-0054),
    not KubernetesPodOperator with a GKE node pool selector.
  - Artifact store is MinIO/Ceph-RGW (s3://, in-DC, ADR-0052) not GCS (gs://).
  - DRA ResourceClaimTemplate for GPU + IB NIC as one unit (ADR-0053).
  - Node selectors use bare-metal labels (platform_system), not GKE pool names.

Instructions:
  1. Copy to apps/infra/airflow/dags/{{DAG_NAME}}.py
  2. Replace all SUBSTITUTE: blocks with real values.
  3. Implement the four # SCAFFOLD task bodies.
  4. See README.md for MinIO/MLflow and Pushgateway integration patterns.

Platform labels (ADR-0028):
  platform.system    = ml-pipeline
  platform.component = airflow
  platform.owner     = {{TEAM_OWNER}}
  platform.env       = {{PLATFORM_ENV}}

UK DC Volcano queue taxonomy (06-uk-datacenters.md, ADR-0054):
  H100 pool: training-default (w100) | training-bootstrap (w30)
             | training-urgent (w200, cap 2 jobs)
  H200 pool: serving-vllm (w150) | eval-judge (w200)
             | engine-build (w80) | batch-rescore (w50)
"""
from __future__ import annotations

import os
from datetime import datetime, timedelta

from airflow.decorators import dag, task
from airflow.models.param import Param

# ---------------------------------------------------------------------------
# Executor config -- CPU task pods on the bare-metal CPU pool (ADR-0049).
# Bare-metal nodes carry platform_system label, not a GKE pool name.
# ---------------------------------------------------------------------------
_CPU_EXECUTOR_CONFIG = {
    "pod_override": {
        "spec": {
            "nodeSelector": {
                # ADR-0028 bare-metal node label
                "platform_system": "cpu-pool",
            },
        }
    }
}

# ---------------------------------------------------------------------------
# VolcanoJob spec template for GPU tasks (ADR-0053 DRA one-DRA-model pattern).
# Rendered at runtime by submit_volcano_job task.
# ADR-0028 labels included on all K8s resources.
# ---------------------------------------------------------------------------
_VOLCANO_JOB_TEMPLATE: dict = {
    "apiVersion": "batch.volcano.sh/v1alpha1",
    "kind": "Job",
    "metadata": {
        "generateName": "{{DAG_NAME}}-",
        # ADR-0028 platform taxonomy labels (K8s dotted form)
        "labels": {
            "platform.system": "ml-pipeline",
            "platform.component": "airflow",
            # SUBSTITUTE: {{PLATFORM_ENV}}
            "platform.env": "{{PLATFORM_ENV}}",
            # SUBSTITUTE: {{TEAM_OWNER}}
            "platform.owner": "{{TEAM_OWNER}}",
            "platform.managed-by": "airflow",
        },
    },
    "spec": {
        # SUBSTITUTE: {{VOLCANO_QUEUE}}
        # UK DC taxonomy -- pick one for your pool/priority.
        "queue": "{{VOLCANO_QUEUE}}",
        # Gang scheduling: all replicas schedulable before any starts.
        # SUBSTITUTE: {{GPU_REPLICAS}}  (DGX H100: 8 GPUs per node)
        "minAvailable": "{{GPU_REPLICAS}}",
        "tasks": [
            {
                "name": "worker",
                # SUBSTITUTE: {{GPU_REPLICAS}}
                "replicas": "{{GPU_REPLICAS}}",
                "template": {
                    "spec": {
                        "schedulerName": "volcano",
                        "nodeSelector": {
                            "platform_system": "gpu-worker",
                            "nvidia.com/gpu.present": "true",
                        },
                        "tolerations": [
                            {
                                "key": "nvidia.com/gpu",
                                "operator": "Exists",
                                "effect": "NoSchedule",
                            }
                        ],
                        # ADR-0053: DRA claim for GPU + IB NIC as one scheduling unit.
                        # ResourceClaimTemplate provisioned by baremetal-gpu-scheduling.
                        "resourceClaims": [
                            {
                                "name": "gpu-ib-claim",
                                "resourceClaimTemplateName": "gpu-ib-h100-template",
                            }
                        ],
                        "containers": [
                            {
                                # SUBSTITUTE: {{TRAINING_IMAGE}}
                                "image": "{{TRAINING_IMAGE}}",
                                "name": "worker",
                                "resources": {
                                    "limits": {
                                        "nvidia.com/gpu": "1",
                                        "resource.k8s.io/gpu-ib-claim": "1",
                                    }
                                },
                                "env": [
                                    # Credentials from Vault/ESO -- never hardcoded.
                                    {
                                        "name": "MINIO_ENDPOINT",
                                        "valueFrom": {
                                            "secretKeyRef": {
                                                # SUBSTITUTE: minio-creds-{{TENANT_ID}}
                                                "name": "minio-creds-{{TENANT_ID}}",
                                                "key": "endpoint",
                                            }
                                        },
                                    },
                                    {
                                        "name": "MINIO_ACCESS_KEY",
                                        "valueFrom": {
                                            "secretKeyRef": {
                                                "name": "minio-creds-{{TENANT_ID}}",
                                                "key": "access_key",
                                            }
                                        },
                                    },
                                    {
                                        "name": "MINIO_SECRET_KEY",
                                        "valueFrom": {
                                            "secretKeyRef": {
                                                "name": "minio-creds-{{TENANT_ID}}",
                                                "key": "secret_key",
                                            }
                                        },
                                    },
                                    {
                                        "name": "MLFLOW_TRACKING_URI",
                                        "valueFrom": {
                                            "secretKeyRef": {
                                                "name": "mlflow-tracking-uri",
                                                "key": "uri",
                                            }
                                        },
                                    },
                                ],
                            }
                        ],
                        "restartPolicy": "Never",
                    }
                },
            }
        ],
    },
}


@dag(
    # SUBSTITUTE: replace {{DAG_NAME}} with your snake_case DAG identifier.
    dag_id="{{DAG_NAME}}",
    # SUBSTITUTE: update the description.
    description="Custom BM ML pipeline: {{DAG_NAME}} (WS-F BM golden path, ADR-0041).",
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
        # SUBSTITUTE: replace {{TENANT}} with your full tenant label.
        "tenant": Param(
            default="{{TENANT}}", type="string", description="Tenant identifier"
        ),
        # SUBSTITUTE: replace {{DOMAIN}} with your ML domain.
        "domain": Param(
            default="{{DOMAIN}}",
            type="string",
            enum=["hft", "solana", "insurance", "rtb"],
            description="ML domain",
        ),
        # SUBSTITUTE: replace {{VOLCANO_QUEUE}} with the target UK DC queue.
        "volcano_queue": Param(
            default="{{VOLCANO_QUEUE}}",
            type="string",
            enum=[
                "training-default",
                "training-bootstrap",
                "training-urgent",
                "serving-vllm",
                "eval-judge",
                "engine-build",
                "batch-rescore",
            ],
            description="UK DC Volcano queue (06-uk-datacenters.md)",
        ),
        "trigger_reason": Param(
            default="manual",
            type="string",
            enum=["manual", "drift", "scheduled"],
            description="Trigger reason (manual | drift | scheduled)",
        ),
    },
    tags=["ml-pipeline", "baremetal", "volcano", "{{DOMAIN}}"],
)
def {{DAG_NAME}}():
    """
    {{DAG_NAME}}: bare-metal ML pipeline DAG (ADR-0041 WS-F BM golden path).

    Platform taxonomy (ADR-0028):
      platform.system    = ml-pipeline
      platform.component = airflow
      platform.owner     = {{TEAM_OWNER}}
      platform.env       = {{PLATFORM_ENV}}
    """

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def ingest_data(**context: dict) -> dict:
        """
        # SCAFFOLD: ingest data from MinIO/Ceph-RGW (s3://, in-DC, ADR-0052),
        # Iceberg snapshot, Kafka, or another source.
        # Return metadata dict for downstream tasks.
        #
        # Example (MinIO via boto3 -- credentials from env, not hardcoded):
        #   import boto3
        #   s3 = boto3.client("s3",
        #       endpoint_url=os.environ["MINIO_ENDPOINT"],
        #       aws_access_key_id=os.environ["MINIO_ACCESS_KEY"],
        #       aws_secret_access_key=os.environ["MINIO_SECRET_KEY"],
        #   )
        #   objs = s3.list_objects_v2(Bucket="{{MINIO_BUCKET}}", Prefix="input/")
        """
        params = context["params"]
        return {
            "tenant": params["tenant"],
            "domain": params["domain"],
            "volcano_queue": params["volcano_queue"],
            "run_id": context["run_id"],
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def submit_volcano_job(ingest_meta: dict, **context: dict) -> dict:
        """
        # SCAFFOLD: render _VOLCANO_JOB_TEMPLATE with runtime values and submit.
        #
        # Steps:
        #   1. Deep-copy _VOLCANO_JOB_TEMPLATE.
        #   2. Replace {{VOLCANO_QUEUE}} with ingest_meta["volcano_queue"].
        #   3. Replace {{GPU_REPLICAS}}, {{TRAINING_IMAGE}}, {{TENANT_ID}}.
        #   4. Submit via kubernetes.client.CustomObjectsApi (incluster config).
        #   5. Poll until the VolcanoJob reaches terminal state (Completed/Failed).
        #
        # NCCL pre-flight (ai-sre/knowledge/nccl-troubleshooting.md):
        #   Embed an nccl-tests all-reduce as the first container init step
        #   to gate that IB fabric is healthy before the real training run.
        #
        # Credentials for MinIO/MLflow come from ESO ExternalSecret in the
        # tenant namespace (charts/tenant-bootstrap/ provisions them).
        """
        return {
            **ingest_meta,
            "job_name": f"{{DAG_NAME}}-{context['run_id'][:8]}",
            "artifact_uri": f"s3://{{MINIO_BUCKET}}/{{MODEL_NAME}}/{context['run_id']}",
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def register_results(job_meta: dict, **context: dict) -> dict:
        """
        # SCAFFOLD: write metrics and artifacts to MLflow with in-DC s3:// backend.
        #
        # Example:
        #   import mlflow
        #   mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
        #   mlflow.set_experiment("{{DAG_NAME}}")
        #   with mlflow.start_run(run_name=job_meta["job_name"]):
        #       mlflow.log_param("volcano_queue", job_meta["volcano_queue"])
        #       mlflow.log_param("tenant", job_meta["tenant"])
        #       mlflow.set_tag("cluster_substrate", "baremetal-uk")
        #       mlflow.log_artifact(local_model_path)
        #       mlflow.register_model(
        #           f"runs:/{mlflow.active_run().info.run_id}/model",
        #           "{{MODEL_NAME}}",
        #       )
        #
        # artifact_uri uses s3:// (MinIO/Ceph-RGW, in-DC) -- NOT gs://.
        # s3_endpoint_url injected from ESO ExternalSecret -- not hardcoded.
        """
        return {
            **job_meta,
            "mlflow_run_id": "placeholder",
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def emit_drift_metrics(result_meta: dict, **context: dict) -> None:
        """
        # SCAFFOLD: push feature distribution metrics to Prometheus Pushgateway
        # for WS-C (Evidently/whylogs) drift tracking.
        #
        # Example:
        #   from prometheus_client import CollectorRegistry, Gauge, push_to_gateway
        #   registry = CollectorRegistry()
        #   g = Gauge("{{DAG_NAME}}_feature_mean", "Mean of feature X",
        #             ["model_name", "tenant", "domain", "cluster_substrate"],
        #             registry=registry)
        #   g.labels(
        #       model_name="{{MODEL_NAME}}",
        #       tenant=result_meta["tenant"],
        #       domain=result_meta["domain"],
        #       cluster_substrate="baremetal-uk",  # distinguishes from GCP/AWS
        #   ).set(feature_mean_value)
        #   push_to_gateway(
        #       "prometheus-pushgateway.ml-monitoring.svc.cluster.local:9091",
        #       job="{{DAG_NAME}}",
        #       registry=registry,
        #   )
        """

    # DAG wiring
    ingest_meta = ingest_data()
    job_meta = submit_volcano_job(ingest_meta)
    result_meta = register_results(job_meta)
    emit_drift_metrics(result_meta)


{{DAG_NAME}}_dag = {{DAG_NAME}}()
