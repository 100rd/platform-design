"""
promote_to_edge — DAG scaffold (ADR-0037 / WS-B)

Triggered by mine_templates after template bundle registration.
Packages, signs, and publishes the adapter as an OCI image for edge deployment.
See docs/transaction-analytics/04-training-pipeline.md.

DAG steps:
  1. merge_lora        — merge LoRA adapter into Qwen 2.5 3B base weights
  2. quantize_fp8      — quantize merged weights to fp8
  3. compile_trtllm    — compile TRT-LLM engine per target_hardware
  4. build_oci_image   — build OCI image with engine + template bundle
  5. sign_and_publish  — syft SBOM + cosign sign + push to OCI registry
  6. register_kargo    — register release candidate in Kargo for progressive rollout

Reproducibility invariant (SOC2 / ADR-0016): every promoted adapter records
  Iceberg snapshot_id, base_model_hash, training_config_hash, training_run_id,
  eval_run_id, bundle_id, cosign_key_id.

Platform labels (ADR-0028): platform.system = ml-pipeline
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow.decorators import dag, task
from airflow.models.param import Param

_CPU_EXECUTOR_CONFIG = {
    "pod_override": {
        "spec": {
            "nodeSelector": {"cloud.google.com/gke-nodepool": "ml-cpu-pool"},
        }
    }
}

_GPU_COMPILE_EXECUTOR_CONFIG = {
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
    dag_id="promote_to_edge",
    description="Package, sign, and publish adapter+templates as a signed OCI edge image.",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=2,
    default_args={
        "retries": 1,
        "retry_delay": timedelta(minutes=10),
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
        "bundle_id": Param(default="", type="string"),
        "mlflow_run_id": Param(default="", type="string"),
        "target_hardware": Param(
            default="h100",
            type="string",
            enum=["h100", "a100", "t4"],
            description="Target GPU for TRT-LLM engine compilation",
        ),
    },
    tags=["ml-pipeline", "promotion", "signing"],
)
def promote_to_edge():
    """
    Package adapter + template bundle as a signed OCI edge image and register
    a Kargo release candidate for progressive rollout (dev → staging → prod).
    """

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def merge_lora(adapter_id: str, tenant: str, domain: str) -> dict:
        """
        Merge LoRA adapter into Qwen 2.5 3B base model weights.
        Base model loaded from Iceberg _platform.models.qwen-2.5-3b/.
        """
        # SCAFFOLD: peft.merge_adapter() + write merged checkpoint to GCS
        return {
            "merged_weights_ref": f"gs://mlflow-artifacts-staging/merged/{adapter_id}",
            "base_model_hash": "scaffold-base-hash",
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def quantize_fp8(merged_ref: dict) -> dict:
        """Quantize merged weights to fp8 for edge deployment."""
        # SCAFFOLD: nvidia ammo toolkit or AutoGPTQ quantization
        return {
            "quantized_weights_ref": merged_ref["merged_weights_ref"] + "-fp8",
        }

    @task(executor_config=_GPU_COMPILE_EXECUTOR_CONFIG)
    def compile_trtllm(quantized_ref: dict, target_hardware: str) -> dict:
        """
        Compile TRT-LLM engine for target_hardware.
        Engine artifacts written to GCS.
        """
        # SCAFFOLD: trtllm-build --checkpoint_dir ... --output_dir ...
        return {
            "engine_ref": quantized_ref["quantized_weights_ref"] + f"-trt-{target_hardware}",
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def build_oci_image(
        engine_ref: dict,
        bundle_id: str,
        adapter_id: str,
        tenant: str,
        domain: str,
        target_hardware: str,
    ) -> dict:
        """
        Build OCI image containing TRT-LLM engine + template bundle.
        Image is held locally pending signing.
        """
        # SCAFFOLD: docker buildx build
        image_tag = f"edge-adapter/{tenant}/{domain}/{adapter_id}-{bundle_id}-{target_hardware}"
        return {
            "image_ref": f"registry.example.com/{image_tag}",
            "image_digest": "sha256:scaffold",
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def sign_and_publish(
        image_ref: dict,
        adapter_id: str,
        bundle_id: str,
        mlflow_run_id: str,
        tenant: str,
        domain: str,
    ) -> dict:
        """
        Generate SBOM (syft) and sign image + attest SBOM via Cosign keyless.
        Mirrors .github/actions/cosign-sign + .github/actions/syft-sbom.

        Cosign key_id recorded in Postgres runs for SOC2 audit chain.
        """
        # SCAFFOLD:
        # subprocess.run(["syft", image_ref["image_ref"], "-o", "spdx-json",
        #                 "--file", "sbom.spdx.json"])
        # subprocess.run(["cosign", "sign", "--yes",
        #                 f"{image_ref['image_ref']}@{image_ref['image_digest']}"])
        # subprocess.run(["cosign", "attest", "--yes", "--type", "spdxjson",
        #                 "--predicate", "sbom.spdx.json",
        #                 f"{image_ref['image_ref']}@{image_ref['image_digest']}"])
        return {
            "signed_image_ref": image_ref["image_ref"],
            "image_digest": image_ref["image_digest"],
            "sbom_ref": f"gs://mlflow-artifacts-staging/sbom/{adapter_id}.spdx.json",
            "cosign_key_id": "scaffold-keyless",
        }

    @task(executor_config=_CPU_EXECUTOR_CONFIG)
    def register_kargo(
        signed_image: dict,
        adapter_id: str,
        bundle_id: str,
        mlflow_run_id: str,
        tenant: str,
        domain: str,
    ) -> None:
        """
        Register Kargo Freight for progressive rollout:
          dev:     auto-approved
          staging: reviewer approval required
          prod:    manual approval + post_deployment_smoke DAG pass

        MLflow model version transitions Staging → Production after prod
        promotion (wired via Kargo WebhookPromotion step). See ADR-0021.
        """
        # SCAFFOLD: create Kargo Freight object
        # POST /api/v1/namespaces/kargo/freights
        # {image: signed_image["signed_image_ref"], digest: signed_image["image_digest"]}

    # -------------------------------------------------------------------------
    # DAG wiring
    # -------------------------------------------------------------------------
    tenant = "{{ params.tenant }}"
    domain = "{{ params.domain }}"
    adapter_id = "{{ params.adapter_id }}"
    bundle_id = "{{ params.bundle_id }}"
    mlflow_run_id = "{{ params.mlflow_run_id }}"
    target_hardware = "{{ params.target_hardware }}"

    merged = merge_lora(adapter_id=adapter_id, tenant=tenant, domain=domain)
    quantized = quantize_fp8(merged_ref=merged)
    engine = compile_trtllm(quantized_ref=quantized, target_hardware=target_hardware)
    image = build_oci_image(
        engine_ref=engine,
        bundle_id=bundle_id,
        adapter_id=adapter_id,
        tenant=tenant,
        domain=domain,
        target_hardware=target_hardware,
    )
    signed = sign_and_publish(
        image_ref=image,
        adapter_id=adapter_id,
        bundle_id=bundle_id,
        mlflow_run_id=mlflow_run_id,
        tenant=tenant,
        domain=domain,
    )
    register_kargo(
        signed_image=signed,
        adapter_id=adapter_id,
        bundle_id=bundle_id,
        mlflow_run_id=mlflow_run_id,
        tenant=tenant,
        domain=domain,
    )


promote_to_edge_dag = promote_to_edge()
