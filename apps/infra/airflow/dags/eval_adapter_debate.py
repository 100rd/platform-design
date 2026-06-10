"""
eval_adapter_debate — DAG scaffold (ADR-0037 / WS-B)

Triggered by train_domain_adapter after adapter registration.
Runs the LLM-as-judge debate gate between candidate and incumbent adapters.
See docs/transaction-analytics/04-training-pipeline.md for the full protocol.

DAG steps:
  1. load_eval_set    — fetch held-out eval set for (tenant, domain) from Iceberg
  2. run_debate       — submit debate evaluation (candidate + incumbent on vLLM
                        multi-LoRA on H200 pool, teacher = Qwen 2.5 72B,
                        judge = independent-family model)
  3. evaluate_gate    — apply per-tenant thresholds (win_rate, p95, strata)
  4. on_pass          — log to MLflow, transition to Staging, trigger mine_templates
  5. on_fail          — log failure, leave adapter in None state, fire alert

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

_GPU_EVAL_EXECUTOR_CONFIG = {
    "pod_override": {
        "spec": {
            "schedulerName": "volcano",
            "nodeSelector": {
                "cloud.google.com/gke-nodepool": "gpu-h200-pool",
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
    dag_id="eval_adapter_debate",
    description="LLM-as-judge debate gate for candidate adapter promotion.",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=3,
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
        "win_rate_threshold": Param(
            default=0.55,
            type="number",
            description="Min fraction of eval items candidate must win vs incumbent",
        ),
    },
    tags=["ml-pipeline", "evaluation", "debate"],
)
def eval_adapter_debate():
    """
    Run LLM-as-judge debate gate. On pass: transition model to Staging and trigger
    mine_templates. On fail: log failure and leave adapter in None state.
    """

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def load_eval_set(tenant: str, domain: str) -> dict:
        """Fetch held-out eval set (10% of training snapshot) from Iceberg."""
        # SCAFFOLD: load held-out split from Iceberg labels table
        return {
            "eval_table": f"scaffold_labels_{domain}_eval",
            "eval_rows": 0,
            "snapshot_id": "scaffold",
        }

    @task(executor_config=_GPU_EVAL_EXECUTOR_CONFIG)
    def run_debate(eval_set_ref: dict, adapter_id: str, tenant: str, domain: str) -> dict:
        """
        Submit debate evaluation on the H200 GPU pool.
        Participants: Candidate (vLLM multi-LoRA), Incumbent (vLLM multi-LoRA),
        Teacher (Qwen 2.5 72B), Judge (Llama 3.3 70B or DeepSeek-V3).

        Protocol per item: each model produces score + rationale;
        judge ranks rationales without seeing scores.
        """
        # SCAFFOLD: submit and poll debate evaluation job
        return {
            "debate_result_id": f"scaffold-debate-{adapter_id}",
            "total_items": 0,
            "win_rate": 0.0,
            "p95_distance_candidate": 0.0,
            "p95_distance_incumbent": 0.0,
            "strata_results": {},
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def evaluate_gate(
        debate_result: dict,
        tenant: str,
        domain: str,
        win_rate_threshold: float,
    ) -> bool:
        """
        Apply per-tenant promotion gate:
          - win_rate > win_rate_threshold (default 0.55)
          - p95_distance_candidate <= p95_distance_incumbent (no regression)
          - No eval strata shows significant degradation
        """
        # SCAFFOLD: read per-tenant thresholds from Postgres and apply
        win_rate = debate_result.get("win_rate", 0.0)
        p95_delta = (
            debate_result.get("p95_distance_candidate", 0.0)
            - debate_result.get("p95_distance_incumbent", 0.0)
        )
        return win_rate > float(win_rate_threshold) and p95_delta <= 0.0

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def on_pass(
        debate_result: dict,
        adapter_id: str,
        mlflow_run_id: str,
        tenant: str,
        domain: str,
    ) -> None:
        """Log eval metrics to MLflow, transition model version to Staging."""
        # SCAFFOLD:
        # client = mlflow.MlflowClient()
        # client.log_metric(mlflow_run_id, "win_rate", debate_result["win_rate"])
        # client.transition_model_version_stage(
        #     name=f"{tenant}.{domain}.adapter", version=..., stage="Staging")

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def on_fail(
        debate_result: dict,
        adapter_id: str,
        mlflow_run_id: str,
        tenant: str,
        domain: str,
    ) -> None:
        """Log eval failure to MLflow. Leave model version in None state."""
        # SCAFFOLD: log failure reason, fire Alertmanager webhook for on-call

    # -------------------------------------------------------------------------
    # DAG wiring
    # -------------------------------------------------------------------------
    tenant = "{{ params.tenant }}"
    domain = "{{ params.domain }}"
    adapter_id = "{{ params.adapter_id }}"
    mlflow_run_id = "{{ params.mlflow_run_id }}"
    threshold = "{{ params.win_rate_threshold }}"

    eval_set = load_eval_set(tenant=tenant, domain=domain)
    debate_result = run_debate(
        eval_set_ref=eval_set,
        adapter_id=adapter_id,
        tenant=tenant,
        domain=domain,
    )
    gate_passed = evaluate_gate(
        debate_result=debate_result,
        tenant=tenant,
        domain=domain,
        win_rate_threshold=threshold,
    )

    trigger_mine = TriggerDagRunOperator(
        task_id="trigger_mine_templates",
        trigger_dag_id="mine_templates",
        conf={
            "tenant": tenant,
            "domain": domain,
            "adapter_id": adapter_id,
            "mlflow_run_id": mlflow_run_id,
        },
        wait_for_completion=False,
    )

    pass_task = on_pass(
        debate_result=debate_result,
        adapter_id=adapter_id,
        mlflow_run_id=mlflow_run_id,
        tenant=tenant,
        domain=domain,
    )
    fail_task = on_fail(
        debate_result=debate_result,
        adapter_id=adapter_id,
        mlflow_run_id=mlflow_run_id,
        tenant=tenant,
        domain=domain,
    )

    gate_passed >> [pass_task, fail_task]  # type: ignore[operator]
    pass_task >> trigger_mine  # type: ignore[operator]


eval_adapter_debate_dag = eval_adapter_debate()
