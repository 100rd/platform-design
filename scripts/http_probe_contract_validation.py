"""Positive and adversarial qualification for the draft HTTP probe contracts."""

from __future__ import annotations

import base64
import copy
import hashlib
import ipaddress
import math
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import rfc8785
import yaml
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)
from jsonschema import Draft202012Validator, FormatChecker, ValidationError
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parents[1]
PROFILE_PATH = (
    ROOT / "platform-contracts/probe-profiles/http-preview-service/v1/profile.yaml"
)
STATE_PRECEDENCE = ("probe-error", "fail", "inconclusive", "pass")


class HttpProbeContractError(Exception):
    pass


def _canonical_bytes(value: Any) -> bytes:
    try:
        return rfc8785.dumps(value)
    except Exception as error:
        raise HttpProbeContractError(f"value is not canonically serializable: {error}") from error


def _digest(value: Any) -> str:
    if isinstance(value, bytes):
        payload = value
    elif isinstance(value, str):
        payload = value.encode("utf-8")
    else:
        payload = _canonical_bytes(value)
    return hashlib.sha256(payload).hexdigest()


def _canonical_digest(value: Any) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


def _without(value: dict[str, Any], dotted_paths: tuple[str, ...]) -> dict[str, Any]:
    result = copy.deepcopy(value)
    for dotted in dotted_paths:
        parent: Any = result
        parts = dotted.split(".")
        for part in parts[:-1]:
            parent = parent[part]
        del parent[parts[-1]]
    return result


def _private_key(label: str) -> Ed25519PrivateKey:
    return Ed25519PrivateKey.from_private_bytes(hashlib.sha256(label.encode()).digest())


def _encode_signature(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _decode_signature(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def _sign(
    value: dict[str, Any],
    private_key: Ed25519PrivateKey,
    excluded: tuple[str, ...],
    signature_path: tuple[str, str],
) -> None:
    payload = _canonical_bytes(_without(value, excluded))
    value[signature_path[0]][signature_path[1]] = _encode_signature(
        private_key.sign(payload)
    )


def _verify_signature(
    value: dict[str, Any],
    signer: dict[str, Any],
    public_key: Ed25519PublicKey,
    expected_profile: str,
    expected_key_id: str,
    excluded: tuple[str, ...],
) -> None:
    if signer["profileDigest"] != expected_profile or signer["signingKeyId"] != expected_key_id:
        raise HttpProbeContractError("signer is not an adapter-owned trust anchor")
    try:
        public_key.verify(
            _decode_signature(signer["signature"]),
            _canonical_bytes(_without(value, excluded)),
        )
    except (InvalidSignature, ValueError) as error:
        raise HttpProbeContractError("cryptographic signature verification failed") from error


def _parse(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _timestamp(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _json_type(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        if not math.isfinite(value):
            raise HttpProbeContractError("non-finite JSON number")
        return "number"
    if isinstance(value, str):
        return "string"
    raise HttpProbeContractError("JSON subset values must be shallow scalars")


def _validate_json_scalar(value: Any) -> str:
    value_type = _json_type(value)
    _canonical_bytes(value)
    return value_type


def _validate_exact_text(value: str) -> None:
    try:
        value.encode("utf-8")
    except UnicodeEncodeError as error:
        raise HttpProbeContractError("exact text is not valid UTF-8") from error


def _validate_acceptance(acceptance: list[dict[str, Any]]) -> None:
    paths = [item["path"] for item in acceptance]
    if len(paths) != len(set(paths)):
        raise HttpProbeContractError("acceptance paths must be unique")
    if [item["ordinal"] for item in acceptance] != list(range(1, len(acceptance) + 1)):
        raise HttpProbeContractError("acceptance ordinals must be contiguous")
    for item in acceptance:
        expected = item["expected"]
        if expected["kind"] == "json-subset":
            for value in expected["jsonSubset"].values():
                _validate_json_scalar(value)
        elif expected["kind"] == "exact-text":
            _validate_exact_text(expected["exactText"])


def validate_http_request_inputs(inputs: dict[str, Any]) -> None:
    paths = [item["path"] for item in inputs["acceptance"]]
    if len(paths) != len(set(paths)):
        raise HttpProbeContractError("request acceptance paths must be unique")
    for item in inputs["acceptance"]:
        expected = item["expected"]
        if "jsonSubset" in expected:
            for value in expected["jsonSubset"].values():
                _validate_json_scalar(value)
        elif "exactText" in expected:
            _validate_exact_text(expected["exactText"])


def _target_snapshot(subject: dict[str, Any]) -> dict[str, Any]:
    service = subject["service"]
    image_digest = subject["delivery"]["imageDigest"]
    pod_name = "payments-api-6d9f7c8b9c-2lmnp"
    pod_uid = "uid-pod-payments-api-1"
    backend = {
        "endpointSliceName": "payments-api-4z2mk",
        "endpointSliceUid": "uid-slice-payments-api",
        "endpointSliceResourceVersion": "401",
        "endpointSliceDigest": _digest("slice-payments-api-401"),
        "endpointSliceServiceName": service["name"],
        "endpointSliceManagedBy": "endpointslice-controller.k8s.io",
        "addressType": "IPv4",
        "address": "10.244.1.9",
        "targetRefKind": "Pod",
        "targetRefName": pod_name,
        "targetRefUid": pod_uid,
        "podNamespace": subject["realm"]["namespaceName"],
        "podName": pod_name,
        "podUid": pod_uid,
        "podResourceVersion": "501",
        "podSpecDigest": _digest("pod-spec-payments-api-1"),
        "podStatusDigest": _digest("pod-status-payments-api-1"),
        "podIp": "10.244.1.9",
        "podOwnerKind": "ReplicaSet",
        "podOwnerName": "payments-api-6d9f7c8b9c",
        "podOwnerUid": "uid-rs-payments-api",
        "replicaSetName": "payments-api-6d9f7c8b9c",
        "replicaSetUid": "uid-rs-payments-api",
        "replicaSetResourceVersion": "601",
        "replicaSetOwnerKind": "Deployment",
        "replicaSetOwnerName": "payments-api",
        "replicaSetOwnerUid": "uid-deployment-payments-api",
        "deploymentName": "payments-api",
        "deploymentUid": "uid-deployment-payments-api",
        "deploymentResourceVersion": "701",
        "renderedPodTemplateDigest": subject["delivery"]["renderedPodTemplateDigest"],
        "ownershipWorkOrderId": subject["workOrderId"],
        "selectorMatches": True,
        "ready": True,
        "serving": True,
        "terminating": False,
        "hostNetwork": False,
        "containerName": "service",
        "containersServingPort": 1,
        "containerPort": 8080,
        "serviceTargetPort": 8080,
        "containerReady": True,
        "imageId": f"containerd://{image_digest}",
        "imageDigest": image_digest,
    }
    endpoint_projection = [
        {
            key: backend[key]
            for key in (
                "endpointSliceName",
                "endpointSliceUid",
                "endpointSliceResourceVersion",
                "endpointSliceDigest",
                "endpointSliceServiceName",
                "endpointSliceManagedBy",
            )
        }
    ]
    return {
        "namespaceUid": subject["realm"]["namespaceUid"],
        "namespaceResourceVersion": subject["realm"]["namespaceResourceVersion"],
        "serviceUid": service["uid"],
        "serviceResourceVersion": service["resourceVersion"],
        "serviceRoutingSpecDigest": service["routingSpecDigest"],
        "networkPolicySetDigest": subject["delivery"]["networkPolicySetDigest"],
        "endpointSliceSetDigest": _digest(endpoint_projection),
        "backendSetDigest": _digest([backend]),
        "observedBackendCount": 1,
        "backends": [backend],
    }


def _refresh_target_digests(target: dict[str, Any]) -> None:
    endpoint_slices: dict[str, dict[str, Any]] = {}
    for backend in target["backends"]:
        endpoint_slices[backend["endpointSliceUid"]] = {
            key: backend[key]
            for key in (
                "endpointSliceName",
                "endpointSliceUid",
                "endpointSliceResourceVersion",
                "endpointSliceDigest",
                "endpointSliceServiceName",
                "endpointSliceManagedBy",
            )
        }
    endpoint_projection = [endpoint_slices[key] for key in sorted(endpoint_slices)]
    target["observedBackendCount"] = len(target["backends"])
    target["endpointSliceSetDigest"] = _digest(endpoint_projection)
    target["backendSetDigest"] = _digest(target["backends"])


def _oracle_for(expected: dict[str, Any]) -> dict[str, Any]:
    if expected["kind"] == "status-only":
        return {"kind": "status-only", "expectedStatus": 200, "observedStatus": 200}
    if expected["kind"] == "exact-text":
        value_digest = _digest(expected["exactText"].encode("utf-8"))
        return {
            "kind": "exact-text",
            "expectedByteDigest": value_digest,
            "observedByteDigest": value_digest,
        }
    entries = []
    for key in sorted(expected["jsonSubset"]):
        value = expected["jsonSubset"][key]
        value_type = _validate_json_scalar(value)
        value_digest = _canonical_digest(value)
        entries.append(
            {
                "key": key,
                "expectedType": value_type,
                "expectedValueDigest": value_digest,
                "observedPresent": True,
                "observedType": value_type,
                "observedValueDigest": value_digest,
            }
        )
    return {"kind": "json-subset", "entries": entries}


def _build_example(
    index: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    subject_private_key = _private_key("http-subject-issuer-v1")
    verifier_private_key = _private_key("http-verifier-v1")
    work_order_id = "httpprobe1"
    run_id = "10000000-0000-4000-8000-000000000001"
    realm_name = f"preview-{work_order_id}"
    image_digest = f"sha256:{_digest('image')}"
    issued_at = datetime(2026, 7, 14, 0, 1, tzinfo=timezone.utc)
    acceptance = [
        {
            "ordinal": 1,
            "method": "GET",
            "path": "/api/v2/payments",
            "expected": {
                "status": 200,
                "kind": "exact-text",
                "mediaType": "text/plain; charset=utf-8",
                "exactText": "ready",
            },
        },
        {
            "ordinal": 2,
            "method": "GET",
            "path": "/api/v2/summary",
            "expected": {
                "status": 200,
                "kind": "json-subset",
                "mediaType": "application/json",
                "jsonSubset": {"count": 2, "status": "ready"},
            },
        },
    ]
    service = {
        "name": "payments-api",
        "uid": "uid-service-payments-api",
        "resourceVersion": "301",
        "routingSpecDigest": _digest("service-routing-spec"),
        "dnsName": f"payments-api.{realm_name}.svc",
        "port": 8080,
    }
    subject = {
        "schemaVersion": "verification/http-probe-subject/v1",
        "workOrderId": work_order_id,
        "runId": run_id,
        "executionEnvelopeDigest": _digest("execution-envelope"),
        "platformPath": "standard-http-service/v3",
        "platformCommitSha": "a" * 40,
        "platformBundleDigest": index["spec"]["bundleDigest"],
        "probeProfile": {
            "id": "http-preview-service/v1",
            "digest": hashlib.sha256(PROFILE_PATH.read_bytes()).hexdigest(),
        },
        "acceptance": acceptance,
        "acceptanceDigest": _digest(acceptance),
        "cluster": {
            "ref": "kubernetes:preview-primary",
            "identityDigest": _digest("preview-cluster-identity"),
            "apiServerDigest": _digest("https://127.0.0.1:6443"),
            "caSha256": _digest("preview-cluster-ca"),
        },
        "realm": {
            "id": "preview/v2",
            "name": realm_name,
            "namespaceName": realm_name,
            "namespaceUid": "uid-namespace-httpprobe1",
            "namespaceResourceVersion": "201",
        },
        "service": service,
        "delivery": {
            "evidenceDigest": _digest("delivery-observation"),
            "observedAt": "2026-07-14T00:00:00Z",
            "expiresAt": "2026-07-15T00:00:00Z",
            "mergeCommitSha": "b" * 40,
            "imageDigest": image_digest,
            "renderedInventoryDigest": _digest("rendered-inventory"),
            "renderedPodTemplateDigest": _digest("rendered-pod-template"),
            "networkPolicySetDigest": _digest("http-verifier-network-policy-set"),
        },
        "issuedAt": _timestamp(issued_at),
        "deadline": _timestamp(issued_at + timedelta(minutes=4)),
        "canonicalization": "rfc8785-json-canonicalization/v1",
        "digestPayloadExcludes": ["subjectSha256", "issuer.signature"],
        "subjectSha256": "0" * 64,
        "issuer": {
            "profileDigest": _digest("http-subject-issuer-profile"),
            "signingKeyId": "kms:http-subject-v1",
            "algorithm": "Ed25519",
            "signature": "0" * 86,
        },
    }
    subject["subjectSha256"] = _digest(
        _without(subject, ("subjectSha256", "issuer.signature"))
    )
    _sign(
        subject,
        subject_private_key,
        ("subjectSha256", "issuer.signature"),
        ("issuer", "signature"),
    )

    descriptors = [
        (
            "health",
            "runtime.health",
            "http.healthz/v1",
            0,
            "/healthz",
            {"kind": "status-only", "status": 200},
        ),
        (
            "readiness",
            "runtime.readiness",
            "http.readyz/v1",
            0,
            "/readyz",
            {"kind": "status-only", "status": 200},
        ),
    ]
    descriptors.extend(
        (
            f"acceptance-{item['ordinal']}",
            "runtime.request-contract",
            "http.request-contract/v1",
            item["ordinal"],
            item["path"],
            item["expected"],
        )
        for item in acceptance
    )
    condition_runs = []
    attempt_sequence = 1
    target = _target_snapshot(subject)
    for condition_id, path_id, probe, expectation_ordinal, path, expected in descriptors:
        attempts = []
        for ordinal in range(1, 4):
            started = issued_at + timedelta(seconds=attempt_sequence * 2)
            completed = started + timedelta(seconds=1)
            oracle = _oracle_for(expected)
            media_type = expected.get("mediaType")
            if expected["kind"] == "exact-text":
                response_payload = expected["exactText"].encode("utf-8")
            elif expected["kind"] == "json-subset":
                response_payload = _canonical_bytes(expected["jsonSubset"])
            else:
                response_payload = b""
            attempts.append(
                {
                    "attemptId": (
                        f"{attempt_sequence:08x}-0000-4000-8000-"
                        f"{attempt_sequence:012x}"
                    ),
                    "ordinal": ordinal,
                    "startedAt": _timestamp(started),
                    "completedAt": _timestamp(completed),
                    "durationMs": 1000,
                    "preTarget": copy.deepcopy(target),
                    "targetErrorCode": None,
                    "backendResults": [
                        {
                            "podUid": target["backends"][0]["podUid"],
                            "state": "pass",
                            "durationMs": 500,
                            "status": 200,
                            "mediaType": media_type,
                            "responseBytes": len(response_payload),
                            "responseTruncated": False,
                            "contentSha256": _digest(response_payload),
                            "errorCode": None,
                            "oracle": oracle,
                        }
                    ],
                    "postTarget": copy.deepcopy(target),
                    "state": "pass",
                }
            )
            attempt_sequence += 1
        condition_runs.append(
            {
                "id": condition_id,
                "pathConditionId": path_id,
                "probe": probe,
                "expectationOrdinal": expectation_ordinal,
                "path": path,
                "expectationDigest": _digest(expected),
                "attempts": attempts,
                "achievedConsecutivePasses": 3,
                "state": "pass",
                "termination": "condition-satisfied",
            }
        )
    result = {
        "schemaVersion": "verification/http-probe-result/v1",
        "evidenceType": "http.probe-result/v1",
        "workOrderId": work_order_id,
        "runId": run_id,
        "subject": subject,
        "subjectSha256": subject["subjectSha256"],
        "conditionRuns": condition_runs,
        "pathConditionResults": [
            {"id": "runtime.health", "state": "pass", "satisfied": True},
            {"id": "runtime.readiness", "state": "pass", "satisfied": True},
            {"id": "runtime.request-contract", "state": "pass", "satisfied": True},
        ],
        "aggregateState": "pass",
        "satisfied": True,
        "startedAt": condition_runs[0]["attempts"][0]["startedAt"],
        "completedAt": condition_runs[-1]["attempts"][-1]["completedAt"],
        "expiresAt": "2026-07-14T01:00:00Z",
        "canonicalization": "rfc8785-json-canonicalization/v1",
        "digestPayloadExcludes": ["evidenceSha256", "verifier.signature"],
        "evidenceSha256": "0" * 64,
        "verifier": {
            "profileDigest": _digest("http-verifier-profile"),
            "signingKeyId": "kms:http-verifier-v1",
            "algorithm": "Ed25519",
            "signature": "0" * 86,
        },
    }
    result["evidenceSha256"] = _digest(
        _without(result, ("evidenceSha256", "verifier.signature"))
    )
    _sign(
        result,
        verifier_private_key,
        ("evidenceSha256", "verifier.signature"),
        ("verifier", "signature"),
    )
    trusted = {
        "executionEnvelope": {
            "digest": subject["executionEnvelopeDigest"],
            "workOrderId": work_order_id,
            "serviceName": service["name"],
            "httpAcceptanceDigest": subject["acceptanceDigest"],
            "platformPath": subject["platformPath"],
            "platformCommitSha": subject["platformCommitSha"],
            "platformBundleDigest": subject["platformBundleDigest"],
        },
        "deliveryEvidence": copy.deepcopy(subject["delivery"]),
        "cluster": copy.deepcopy(subject["cluster"]),
        "realm": copy.deepcopy(subject["realm"]),
        "service": copy.deepcopy(subject["service"]),
        "subjectIssuer": {
            "profileDigest": subject["issuer"]["profileDigest"],
            "signingKeyId": subject["issuer"]["signingKeyId"],
            "publicKey": subject_private_key.public_key(),
            "privateKey": subject_private_key,
        },
        "verifier": {
            "profileDigest": result["verifier"]["profileDigest"],
            "signingKeyId": result["verifier"]["signingKeyId"],
            "publicKey": verifier_private_key.public_key(),
            "privateKey": verifier_private_key,
        },
    }
    return subject, result, trusted


def _state_from(values: list[str]) -> str:
    if not values:
        return "inconclusive"
    for state in STATE_PRECEDENCE:
        if state in values:
            return state
    raise HttpProbeContractError("unknown result state")


def _backend_state(result: dict[str, Any], expected: dict[str, Any]) -> str:
    error = result["errorCode"]
    if error is not None:
        return "inconclusive" if error == "run-deadline" else "probe-error"
    if (
        result["status"] != 200
        or result["responseBytes"] > 65536
        or result["responseTruncated"]
    ):
        return "fail"
    oracle = result["oracle"]
    if expected["kind"] == "status-only":
        return "pass" if oracle == {
            "kind": "status-only",
            "expectedStatus": 200,
            "observedStatus": 200,
        } else "fail"
    if result["mediaType"] != expected["mediaType"]:
        return "fail"
    if expected["kind"] == "exact-text":
        expected_digest = _digest(expected["exactText"].encode("utf-8"))
        if (
            result["contentSha256"] != expected_digest
            or result["responseBytes"] != len(expected["exactText"].encode("utf-8"))
        ):
            return "fail"
        return "pass" if oracle == {
            "kind": "exact-text",
            "expectedByteDigest": expected_digest,
            "observedByteDigest": expected_digest,
        } else "fail"
    expected_entries = _oracle_for(expected)["entries"]
    if result["contentSha256"] is None or result["responseBytes"] == 0:
        return "fail"
    return "pass" if oracle == {
        "kind": "json-subset",
        "entries": expected_entries,
    } else "fail"


def _validate_target(
    target: dict[str, Any], subject: dict[str, Any]
) -> tuple[list[str], str | None]:
    service = subject["service"]
    realm = subject["realm"]
    target_error: str | None = None
    if (
        target["namespaceUid"] != realm["namespaceUid"]
        or target["namespaceResourceVersion"] != realm["namespaceResourceVersion"]
    ):
        target_error = "invalid-backend"
    if (
        target["serviceUid"] != service["uid"]
        or target["serviceResourceVersion"] != service["resourceVersion"]
        or target["serviceRoutingSpecDigest"] != service["routingSpecDigest"]
    ):
        target_error = "invalid-backend"
    if target["networkPolicySetDigest"] != subject["delivery"]["networkPolicySetDigest"]:
        target_error = "invalid-backend"
    backends = target["backends"]
    if target["observedBackendCount"] != len(backends):
        raise HttpProbeContractError("observed backend count is false")
    if not backends:
        target_error = "empty-backend-set"
    elif len(backends) > 3:
        target_error = "excess-backend-set"
    backend_order_keys = [
        (
            "pod",
            backend["podUid"],
            backend["endpointSliceUid"],
            backend["address"],
        )
        if backend["podUid"] is not None
        else (
            "endpoint",
            backend["endpointSliceUid"],
            backend["address"],
            backend["targetRefUid"] or "",
        )
        for backend in backends
    ]
    if backend_order_keys != sorted(set(backend_order_keys)):
        target_error = "invalid-backend"
    pod_uids = [
        backend["podUid"] for backend in backends if backend["podUid"] is not None
    ]
    if len(pod_uids) != len(backends) or pod_uids != sorted(set(pod_uids)):
        target_error = "invalid-backend"
    endpoint_slices: dict[str, dict[str, Any]] = {}
    for backend in backends:
        required_identity_fields = (
            "targetRefName",
            "targetRefUid",
            "podNamespace",
            "podName",
            "podUid",
            "podOwnerName",
            "podOwnerUid",
            "replicaSetName",
            "replicaSetUid",
            "replicaSetOwnerName",
            "replicaSetOwnerUid",
            "deploymentName",
            "deploymentUid",
            "containerName",
        )
        if any(backend[field] is None for field in required_identity_fields):
            target_error = "invalid-backend"
        try:
            address = ipaddress.ip_address(backend["address"])
        except ValueError:
            target_error = "invalid-backend"
            address = None
        expected_address_type = (
            "IPv4" if address is not None and address.version == 4 else "IPv6"
        )
        if (
            backend["address"] != backend["podIp"]
            or backend["addressType"] != expected_address_type
            or backend["endpointSliceServiceName"] != service["name"]
            or backend["endpointSliceManagedBy"]
            != "endpointslice-controller.k8s.io"
            or backend["targetRefKind"] != "Pod"
            or backend["targetRefName"] != backend["podName"]
            or backend["targetRefUid"] != backend["podUid"]
            or backend["podNamespace"] != realm["namespaceName"]
            or backend["podResourceVersion"] is None
            or backend["podSpecDigest"] is None
            or backend["podStatusDigest"] is None
            or backend["podOwnerKind"] != "ReplicaSet"
            or backend["podOwnerName"] != backend["replicaSetName"]
            or backend["podOwnerUid"] != backend["replicaSetUid"]
            or backend["replicaSetResourceVersion"] is None
            or backend["replicaSetOwnerKind"] != "Deployment"
            or backend["replicaSetOwnerName"] != backend["deploymentName"]
            or backend["replicaSetOwnerUid"] != backend["deploymentUid"]
            or backend["deploymentName"] != service["name"]
            or backend["deploymentResourceVersion"] is None
            or backend["renderedPodTemplateDigest"]
            != subject["delivery"]["renderedPodTemplateDigest"]
            or backend["ownershipWorkOrderId"] != subject["workOrderId"]
            or not backend["selectorMatches"]
            or not backend["ready"]
            or not backend["serving"]
            or backend["terminating"]
            or backend["hostNetwork"]
            or backend["containersServingPort"] != 1
            or backend["containerPort"] != service["port"]
            or backend["serviceTargetPort"] != service["port"]
            or not backend["containerReady"]
        ):
            target_error = "invalid-backend"
        if backend["imageDigest"] is None:
            target_error = "invalid-backend"
        elif backend["imageDigest"] != subject["delivery"]["imageDigest"]:
            target_error = "mixed-image"
        if (
            backend["imageId"] is None
            or backend["imageDigest"] is None
            or backend["imageId"]
            not in {
                f"containerd://{backend['imageDigest']}",
                f"docker-pullable://{backend['imageDigest']}",
            }
        ):
            target_error = "invalid-backend"
        projection = {
            key: backend[key]
            for key in (
                "endpointSliceName",
                "endpointSliceUid",
                "endpointSliceResourceVersion",
                "endpointSliceDigest",
                "endpointSliceServiceName",
                "endpointSliceManagedBy",
            )
        }
        existing = endpoint_slices.setdefault(backend["endpointSliceUid"], projection)
        if existing != projection:
            raise HttpProbeContractError("EndpointSlice identity is internally inconsistent")
    endpoint_projection = [endpoint_slices[key] for key in sorted(endpoint_slices)]
    if target["endpointSliceSetDigest"] != _digest(endpoint_projection):
        raise HttpProbeContractError("EndpointSlice set digest is false")
    if target["backendSetDigest"] != _digest(backends):
        raise HttpProbeContractError("backend set digest is false")
    return pod_uids, target_error


def _validate_semantics(
    subject: dict[str, Any],
    result: dict[str, Any],
    index: dict[str, Any],
    trusted: dict[str, Any],
) -> None:
    if subject["platformBundleDigest"] != index["spec"]["bundleDigest"]:
        raise HttpProbeContractError("subject is bound to another platform bundle")
    profile_digest = hashlib.sha256(PROFILE_PATH.read_bytes()).hexdigest()
    if subject["probeProfile"] != {
        "id": "http-preview-service/v1",
        "digest": profile_digest,
    }:
        raise HttpProbeContractError("subject is bound to another probe profile")
    _verify_signature(
        subject,
        subject["issuer"],
        trusted["subjectIssuer"]["publicKey"],
        trusted["subjectIssuer"]["profileDigest"],
        trusted["subjectIssuer"]["signingKeyId"],
        ("subjectSha256", "issuer.signature"),
    )
    envelope = trusted["executionEnvelope"]
    expected_envelope = {
        "digest": subject["executionEnvelopeDigest"],
        "workOrderId": subject["workOrderId"],
        "serviceName": subject["service"]["name"],
        "httpAcceptanceDigest": subject["acceptanceDigest"],
        "platformPath": subject["platformPath"],
        "platformCommitSha": subject["platformCommitSha"],
        "platformBundleDigest": subject["platformBundleDigest"],
    }
    if envelope != expected_envelope:
        raise HttpProbeContractError("subject does not join the trusted execution envelope")
    if subject["delivery"] != trusted["deliveryEvidence"]:
        raise HttpProbeContractError("subject does not join trusted delivery evidence")
    if subject["cluster"] != trusted["cluster"]:
        raise HttpProbeContractError("subject does not join the adapter cluster identity")
    if subject["realm"] != trusted["realm"] or subject["service"] != trusted["service"]:
        raise HttpProbeContractError("subject target does not join trusted delivery identity")
    _validate_acceptance(subject["acceptance"])
    if subject["acceptanceDigest"] != _digest(subject["acceptance"]):
        raise HttpProbeContractError("acceptance digest is false")
    expected_subject_digest = _digest(
        _without(subject, ("subjectSha256", "issuer.signature"))
    )
    if subject["subjectSha256"] != expected_subject_digest:
        raise HttpProbeContractError("subject digest is false")
    observed_at = _parse(subject["delivery"]["observedAt"])
    delivery_expiry = _parse(subject["delivery"]["expiresAt"])
    issued_at = _parse(subject["issuedAt"])
    deadline = _parse(subject["deadline"])
    if not observed_at <= issued_at <= observed_at + timedelta(minutes=5):
        raise HttpProbeContractError("delivery observation is stale")
    if not issued_at < deadline <= issued_at + timedelta(minutes=4):
        raise HttpProbeContractError("subject deadline is outside the profile")
    if deadline > delivery_expiry:
        raise HttpProbeContractError("subject outlives delivery evidence")
    if subject["realm"]["name"] != subject["realm"]["namespaceName"]:
        raise HttpProbeContractError("Realm and Namespace identity differ")
    expected_dns = f"{subject['service']['name']}.{subject['realm']['namespaceName']}.svc"
    if subject["service"]["dnsName"] != expected_dns:
        raise HttpProbeContractError("Service DNS name is not derived")
    expected_realm = f"preview-{subject['workOrderId']}"
    if subject["realm"]["name"] != expected_realm:
        raise HttpProbeContractError("Realm is not derived from WorkOrder")

    if result["subject"] != subject or result["subjectSha256"] != subject["subjectSha256"]:
        raise HttpProbeContractError("result is not bound to its signed subject")
    if result["workOrderId"] != subject["workOrderId"]:
        raise HttpProbeContractError("cross-WorkOrder result")
    if result["runId"] != subject["runId"]:
        raise HttpProbeContractError("cross-run result")
    _verify_signature(
        result,
        result["verifier"],
        trusted["verifier"]["publicKey"],
        trusted["verifier"]["profileDigest"],
        trusted["verifier"]["signingKeyId"],
        ("evidenceSha256", "verifier.signature"),
    )

    descriptors = [
        (
            "health",
            "runtime.health",
            "http.healthz/v1",
            0,
            "/healthz",
            {"kind": "status-only", "status": 200},
        ),
        (
            "readiness",
            "runtime.readiness",
            "http.readyz/v1",
            0,
            "/readyz",
            {"kind": "status-only", "status": 200},
        ),
    ]
    descriptors.extend(
        (
            f"acceptance-{item['ordinal']}",
            "runtime.request-contract",
            "http.request-contract/v1",
            item["ordinal"],
            item["path"],
            item["expected"],
        )
        for item in subject["acceptance"]
    )
    if len(result["conditionRuns"]) != len(descriptors):
        raise HttpProbeContractError("condition run set is incomplete")

    global_attempt_ids: set[str] = set()
    derived_condition_states: dict[str, list[str]] = {
        "runtime.health": [],
        "runtime.readiness": [],
        "runtime.request-contract": [],
    }
    all_attempt_times: list[tuple[datetime, datetime]] = []
    previous_global_completion: datetime | None = None
    run_deadline_reached = False
    for condition, descriptor in zip(result["conditionRuns"], descriptors, strict=True):
        condition_id, path_id, probe, expectation_ordinal, path, expected = descriptor
        if (
            condition["id"],
            condition["pathConditionId"],
            condition["probe"],
            condition["expectationOrdinal"],
            condition["path"],
            condition["expectationDigest"],
        ) != (condition_id, path_id, probe, expectation_ordinal, path, _digest(expected)):
            raise HttpProbeContractError("condition expansion differs from frozen expectations")
        attempt_states: list[str] = []
        streak = 0
        achieved = 0
        attempts = condition["attempts"]
        if run_deadline_reached and attempts:
            raise HttpProbeContractError("attempt recorded after the global run deadline")
        previous_condition_completion: datetime | None = None
        if [attempt["ordinal"] for attempt in attempts] != list(range(1, len(attempts) + 1)):
            raise HttpProbeContractError("attempt ordinals must be contiguous")
        for attempt in attempts:
            if attempt["attemptId"] in global_attempt_ids:
                raise HttpProbeContractError("attempt ID is reused")
            global_attempt_ids.add(attempt["attemptId"])
            started = _parse(attempt["startedAt"])
            completed = _parse(attempt["completedAt"])
            actual_duration = int((completed - started).total_seconds() * 1000)
            if actual_duration != attempt["durationMs"] or not issued_at <= started < completed:
                raise HttpProbeContractError("attempt time or duration is false")
            if completed > deadline or attempt["durationMs"] > 30000:
                raise HttpProbeContractError("attempt exceeds signed deadline")
            if previous_global_completion is not None and started < previous_global_completion:
                raise HttpProbeContractError("condition attempts overlap or are reordered")
            if (
                previous_condition_completion is not None
                and started < previous_condition_completion + timedelta(seconds=1)
            ):
                raise HttpProbeContractError("PT1S attempt delay is not satisfied")
            previous_condition_completion = completed
            previous_global_completion = completed
            all_attempt_times.append((started, completed))

            pre_uids, pre_error = _validate_target(attempt["preTarget"], subject)
            post_uids, post_error = _validate_target(attempt["postTarget"], subject)
            target_error = pre_error or post_error
            if attempt["preTarget"] != attempt["postTarget"] or pre_uids != post_uids:
                target_error = "target-drift"
            if attempt["targetErrorCode"] != target_error:
                raise HttpProbeContractError("target error is falsely classified")
            if target_error is not None:
                if attempt["backendResults"]:
                    raise HttpProbeContractError("invalid target must not be probed")
                batch_state = "probe-error"
            else:
                result_uids = [item["podUid"] for item in attempt["backendResults"]]
                if result_uids != pre_uids:
                    raise HttpProbeContractError("backend result set differs from target snapshot")
                backend_states = []
                for item in attempt["backendResults"]:
                    if item["durationMs"] > 5000 or item["durationMs"] > attempt["durationMs"]:
                        raise HttpProbeContractError("backend request exceeds PT5S deadline")
                    derived_backend_state = _backend_state(item, expected)
                    if item["state"] != derived_backend_state:
                        raise HttpProbeContractError("backend state is falsely asserted")
                    backend_states.append(derived_backend_state)
                batch_state = _state_from(backend_states)
            if attempt["state"] != batch_state:
                raise HttpProbeContractError("attempt batch state is falsely reduced")
            attempt_states.append(batch_state)
            streak = streak + 1 if batch_state == "pass" else 0
            achieved = max(achieved, min(streak, 3))
            if achieved == 3 and attempt["ordinal"] != len(attempts):
                raise HttpProbeContractError(
                    "condition continued after three consecutive passes"
                )
        if (
            "probe-error" in attempt_states
            and attempt_states.index("probe-error") != len(attempt_states) - 1
        ):
            raise HttpProbeContractError("probe-error did not stop the condition run")
        non_pass_states = [state for state in attempt_states if state != "pass"]
        final_state = (
            "pass"
            if achieved == 3
            else _state_from(non_pass_states)
            if non_pass_states
            else "inconclusive"
        )
        if condition["state"] != final_state:
            raise HttpProbeContractError("condition state is falsely reduced")
        if condition["achievedConsecutivePasses"] != achieved:
            raise HttpProbeContractError("consecutive-pass count is false")
        expected_termination = (
            "condition-satisfied"
            if final_state == "pass"
            else "probe-error"
            if final_state == "probe-error"
            else "attempts-exhausted"
            if len(attempts) == 5
            else "run-deadline"
        )
        if condition["termination"] != expected_termination:
            raise HttpProbeContractError("condition termination is false")
        if expected_termination == "run-deadline":
            run_deadline_reached = True
        derived_condition_states[path_id].append(final_state)

    path_states = {
        path_id: _state_from(states)
        for path_id, states in derived_condition_states.items()
    }
    expected_path_results = [
        {
            "id": path_id,
            "state": path_states[path_id],
            "satisfied": path_states[path_id] == "pass",
        }
        for path_id in (
            "runtime.health",
            "runtime.readiness",
            "runtime.request-contract",
        )
    ]
    if result["pathConditionResults"] != expected_path_results:
        raise HttpProbeContractError("path Condition of Done reduction is false")
    aggregate = _state_from(list(path_states.values()))
    if result["aggregateState"] != aggregate or result["satisfied"] != (aggregate == "pass"):
        raise HttpProbeContractError("overall HTTP result reduction is false")
    started_at = _parse(result["startedAt"])
    completed_at = _parse(result["completedAt"])
    expires_at = _parse(result["expiresAt"])
    expected_start = all_attempt_times[0][0] if all_attempt_times else issued_at
    expected_completion = (
        deadline
        if run_deadline_reached or not all_attempt_times
        else all_attempt_times[-1][1]
    )
    if started_at != expected_start:
        raise HttpProbeContractError("run start is false")
    if completed_at != expected_completion:
        raise HttpProbeContractError("run completion is false")
    if not issued_at <= started_at < completed_at <= deadline < expires_at <= delivery_expiry:
        raise HttpProbeContractError("run evidence time ordering is invalid")
    expected_evidence_digest = _digest(
        _without(result, ("evidenceSha256", "verifier.signature"))
    )
    if result["evidenceSha256"] != expected_evidence_digest:
        raise HttpProbeContractError("HTTP evidence digest is false")


def _redigest_subject(
    subject: dict[str, Any], private_key: Ed25519PrivateKey
) -> None:
    subject["subjectSha256"] = _digest(
        _without(subject, ("subjectSha256", "issuer.signature"))
    )
    _sign(
        subject,
        private_key,
        ("subjectSha256", "issuer.signature"),
        ("issuer", "signature"),
    )


def _redigest_result(
    result: dict[str, Any], private_key: Ed25519PrivateKey
) -> None:
    result["subjectSha256"] = result["subject"]["subjectSha256"]
    result["evidenceSha256"] = _digest(
        _without(result, ("evidenceSha256", "verifier.signature"))
    )
    _sign(
        result,
        private_key,
        ("evidenceSha256", "verifier.signature"),
        ("verifier", "signature"),
    )


def _make_target_error_result(
    result: dict[str, Any],
    target_error: str,
    private_key: Ed25519PrivateKey,
    *,
    pre_target: dict[str, Any] | None = None,
    post_target: dict[str, Any] | None = None,
) -> dict[str, Any]:
    mutated = copy.deepcopy(result)
    condition = mutated["conditionRuns"][0]
    attempt = condition["attempts"][0]
    if pre_target is not None:
        attempt["preTarget"] = pre_target
    if post_target is not None:
        attempt["postTarget"] = post_target
    attempt["targetErrorCode"] = target_error
    attempt["backendResults"] = []
    attempt["state"] = "probe-error"
    condition["attempts"] = [attempt]
    condition["achievedConsecutivePasses"] = 0
    condition["state"] = "probe-error"
    condition["termination"] = "probe-error"
    mutated["pathConditionResults"][0] = {
        "id": "runtime.health",
        "state": "probe-error",
        "satisfied": False,
    }
    mutated["aggregateState"] = "probe-error"
    mutated["satisfied"] = False
    _redigest_result(mutated, private_key)
    return mutated


def validate_http_probe_contracts(
    schemas: dict[str, Any], index: dict[str, Any]
) -> None:
    if (
        _canonical_bytes(1.0) != b"1"
        or _canonical_bytes({"z": 1, "a": 2}) != b'{"a":2,"z":1}'
    ):
        raise HttpProbeContractError("RFC 8785 canonicalization regression")
    registry = Registry().with_resources(
        (schema_id, Resource.from_contents(schema))
        for schema_id, schema in schemas.items()
    )
    subject_schema = "urn:darkfactory:platform-contract:http-probe-subject:v1"
    result_schema = "urn:darkfactory:platform-contract:http-probe-result:v1"
    subject_validator = Draft202012Validator(
        schemas[subject_schema], registry=registry, format_checker=FormatChecker()
    )
    result_validator = Draft202012Validator(
        schemas[result_schema], registry=registry, format_checker=FormatChecker()
    )
    subject, result, trusted = _build_example(index)
    subject_private_key = trusted["subjectIssuer"]["privateKey"]
    verifier_private_key = trusted["verifier"]["privateKey"]
    subject_validator.validate(subject)
    result_validator.validate(result)
    _validate_semantics(subject, result, index, trusted)

    profile_schema = "urn:darkfactory:platform-contract:http-probe-profile:v1"
    profile_validator = Draft202012Validator(
        schemas[profile_schema], registry=registry, format_checker=FormatChecker()
    )
    with PROFILE_PATH.open(encoding="utf-8") as stream:
        profile = yaml.safe_load(stream)
    profile_validator.validate(profile)

    request_schema = schemas[
        "urn:darkfactory:platform-contract:path-input:standard-http-service:v3"
    ]
    request_validator = Draft202012Validator(request_schema)
    valid_inputs = {
        "serviceName": "payments-api",
        "ownerRef": "team:payments",
        "repositoryRef": "github:100rd/payments-api",
        "sourceSubpath": "service",
        "runtime": "go-1.23",
        "exposure": "internal",
        "port": 8080,
        "resourceProfile": "small",
        "acceptance": [
            {
                "method": "GET",
                "path": "/api/v2/payments",
                "expected": {
                    "status": 200,
                    "mediaType": "text/plain; charset=utf-8",
                    "exactText": "ready",
                },
            },
            {
                "method": "GET",
                "path": "/api/v2/summary",
                "expected": {
                    "status": 200,
                    "mediaType": "application/json",
                    "jsonSubset": {"count": 2, "status": "ready"},
                },
            },
        ],
    }
    request_validator.validate(valid_inputs)
    validate_http_request_inputs(valid_inputs)

    structural_mutations: list[tuple[str, Draft202012Validator, dict[str, Any]]] = []
    raw_body = copy.deepcopy(result)
    raw_body["conditionRuns"][0]["attempts"][0]["backendResults"][0][
        "rawResponse"
    ] = "must-not-be-stored"
    structural_mutations.append(("raw response retention", result_validator, raw_body))
    bad_path = copy.deepcopy(valid_inputs)
    bad_path["acceptance"][0]["path"] = "//attacker/path"
    structural_mutations.append(("network-path acceptance", request_validator, bad_path))
    bad_media = copy.deepcopy(valid_inputs)
    bad_media["acceptance"][0]["expected"]["mediaType"] = "application/json"
    structural_mutations.append(("oracle media mismatch", request_validator, bad_media))
    redirected = copy.deepcopy(profile)
    redirected["transport"]["redirects"] = True
    structural_mutations.append(("redirect-enabled profile", profile_validator, redirected))
    caller_target = copy.deepcopy(profile)
    caller_target["targetResolution"]["hostFrom"] = "request.inputs.host"
    structural_mutations.append(("caller target profile", profile_validator, caller_target))
    worker_evidence = copy.deepcopy(profile)
    worker_evidence["evidence"]["workerEvidenceAccepted"] = True
    structural_mutations.append(("worker evidence profile", profile_validator, worker_evidence))
    for name, validator, value in structural_mutations:
        try:
            validator.validate(value)
        except ValidationError:
            continue
        raise HttpProbeContractError(f"invalid structural mutation passed: {name}")

    duplicate_inputs = copy.deepcopy(valid_inputs)
    duplicate_inputs["acceptance"].append(copy.deepcopy(duplicate_inputs["acceptance"][0]))
    try:
        request_validator.validate(duplicate_inputs)
        validate_http_request_inputs(duplicate_inputs)
    except HttpProbeContractError:
        pass
    else:
        raise HttpProbeContractError("invalid request semantic mutation passed: duplicate path")

    noncanonical_inputs = copy.deepcopy(valid_inputs)
    noncanonical_inputs["acceptance"][1]["expected"]["jsonSubset"]["count"] = 2**53
    try:
        request_validator.validate(noncanonical_inputs)
        validate_http_request_inputs(noncanonical_inputs)
    except HttpProbeContractError:
        pass
    else:
        raise HttpProbeContractError(
            "invalid request semantic mutation passed: noncanonical JSON integer"
        )

    non_utf8_inputs = copy.deepcopy(valid_inputs)
    non_utf8_inputs["acceptance"][0]["expected"]["exactText"] = "\ud800"
    try:
        request_validator.validate(non_utf8_inputs)
        validate_http_request_inputs(non_utf8_inputs)
    except HttpProbeContractError:
        pass
    else:
        raise HttpProbeContractError(
            "invalid request semantic mutation passed: non-UTF-8 exact text"
        )

    duplicate_subject_acceptance = [
        {**item, "ordinal": position}
        for position, item in enumerate(subject["acceptance"] * 2, start=1)
    ]
    semantic_input_mutations = [
        ("duplicate acceptance path", duplicate_subject_acceptance),
        (
            "non-finite JSON subset",
            [
                {
                    "ordinal": 1,
                    "method": "GET",
                    "path": "/api/value",
                    "expected": {
                        "status": 200,
                        "kind": "json-subset",
                        "mediaType": "application/json",
                        "jsonSubset": {"value": float("nan")},
                    },
                }
            ],
        ),
        (
            "noncanonical JSON integer",
            [
                {
                    "ordinal": 1,
                    "method": "GET",
                    "path": "/api/value",
                    "expected": {
                        "status": 200,
                        "kind": "json-subset",
                        "mediaType": "application/json",
                        "jsonSubset": {"value": 2**53},
                    },
                }
            ],
        ),
    ]
    for name, acceptance in semantic_input_mutations:
        try:
            _validate_acceptance(acceptance)
        except HttpProbeContractError:
            continue
        raise HttpProbeContractError(f"invalid request semantic mutation passed: {name}")

    base_target = result["conditionRuns"][0]["attempts"][0]["preTarget"]
    empty_target = copy.deepcopy(base_target)
    empty_target["backends"] = []
    _refresh_target_digests(empty_target)

    excess_target = copy.deepcopy(base_target)
    excess_target["backends"] = []
    for ordinal in range(1, 5):
        backend = copy.deepcopy(base_target["backends"][0])
        suffix = str(ordinal)
        pod_name = f"payments-api-6d9f7c8b9c-{suffix}"
        pod_uid = f"uid-pod-payments-api-{suffix}"
        pod_ip = f"10.244.1.{8 + ordinal}"
        backend.update(
            {
                "address": pod_ip,
                "targetRefName": pod_name,
                "targetRefUid": pod_uid,
                "podName": pod_name,
                "podUid": pod_uid,
                "podResourceVersion": str(500 + ordinal),
                "podSpecDigest": _digest(f"pod-spec-payments-api-{suffix}"),
                "podStatusDigest": _digest(f"pod-status-payments-api-{suffix}"),
                "podIp": pod_ip,
            }
        )
        excess_target["backends"].append(backend)
    _refresh_target_digests(excess_target)

    mixed_target = copy.deepcopy(base_target)
    foreign_image = f"sha256:{_digest('foreign-image')}"
    mixed_target["backends"][0]["imageDigest"] = foreign_image
    mixed_target["backends"][0]["imageId"] = f"containerd://{foreign_image}"
    _refresh_target_digests(mixed_target)

    drift_target = copy.deepcopy(base_target)
    drift_target["serviceResourceVersion"] = "302"

    invalid_target = copy.deepcopy(base_target)
    invalid_target["networkPolicySetDigest"] = _digest("foreign-network-policy-set")

    unready_target = copy.deepcopy(base_target)
    unready_backend = unready_target["backends"][0]
    unready_backend["ready"] = False
    unready_backend["serving"] = False
    unready_backend["containerReady"] = False
    _refresh_target_digests(unready_target)

    external_target = copy.deepcopy(base_target)
    external_backend = external_target["backends"][0]
    for field in (
        "targetRefKind",
        "targetRefName",
        "targetRefUid",
        "podNamespace",
        "podName",
        "podUid",
        "podResourceVersion",
        "podSpecDigest",
        "podStatusDigest",
        "podIp",
        "podOwnerKind",
        "podOwnerName",
        "podOwnerUid",
        "replicaSetName",
        "replicaSetUid",
        "replicaSetResourceVersion",
        "replicaSetOwnerKind",
        "replicaSetOwnerName",
        "replicaSetOwnerUid",
        "deploymentName",
        "deploymentUid",
        "deploymentResourceVersion",
        "renderedPodTemplateDigest",
        "ownershipWorkOrderId",
        "containerName",
        "containerPort",
        "imageId",
        "imageDigest",
    ):
        external_backend[field] = None
    external_backend.update(
        {
            "address": "192.0.2.10",
            "selectorMatches": False,
            "ready": True,
            "serving": True,
            "containersServingPort": 0,
            "containerReady": False,
        }
    )
    _refresh_target_digests(external_target)

    valid_target_outcomes = [
        (
            "empty backend set",
            _make_target_error_result(
                result,
                "empty-backend-set",
                verifier_private_key,
                pre_target=copy.deepcopy(empty_target),
                post_target=copy.deepcopy(empty_target),
            ),
        ),
        (
            "excess backend set",
            _make_target_error_result(
                result,
                "excess-backend-set",
                verifier_private_key,
                pre_target=copy.deepcopy(excess_target),
                post_target=copy.deepcopy(excess_target),
            ),
        ),
        (
            "mixed image set",
            _make_target_error_result(
                result,
                "mixed-image",
                verifier_private_key,
                pre_target=copy.deepcopy(mixed_target),
                post_target=copy.deepcopy(mixed_target),
            ),
        ),
        (
            "target drift",
            _make_target_error_result(
                result,
                "target-drift",
                verifier_private_key,
                pre_target=copy.deepcopy(base_target),
                post_target=drift_target,
            ),
        ),
        (
            "invalid network target",
            _make_target_error_result(
                result,
                "invalid-backend",
                verifier_private_key,
                pre_target=copy.deepcopy(invalid_target),
                post_target=copy.deepcopy(invalid_target),
            ),
        ),
        (
            "unready backend",
            _make_target_error_result(
                result,
                "invalid-backend",
                verifier_private_key,
                pre_target=copy.deepcopy(unready_target),
                post_target=copy.deepcopy(unready_target),
            ),
        ),
        (
            "external endpoint",
            _make_target_error_result(
                result,
                "invalid-backend",
                verifier_private_key,
                pre_target=copy.deepcopy(external_target),
                post_target=copy.deepcopy(external_target),
            ),
        ),
    ]
    for name, outcome in valid_target_outcomes:
        try:
            result_validator.validate(outcome)
            _validate_semantics(outcome["subject"], outcome, index, trusted)
        except (HttpProbeContractError, ValidationError) as error:
            raise HttpProbeContractError(
                f"valid signed target outcome failed: {name}: {error}"
            ) from error

    deadline_outcome = copy.deepcopy(result)
    deadline_condition = deadline_outcome["conditionRuns"][-1]
    deadline_condition.update(
        {
            "attempts": [],
            "achievedConsecutivePasses": 0,
            "state": "inconclusive",
            "termination": "run-deadline",
        }
    )
    deadline_outcome["pathConditionResults"][2] = {
        "id": "runtime.request-contract",
        "state": "inconclusive",
        "satisfied": False,
    }
    deadline_outcome["aggregateState"] = "inconclusive"
    deadline_outcome["satisfied"] = False
    deadline_outcome["completedAt"] = deadline_outcome["subject"]["deadline"]
    _redigest_result(deadline_outcome, verifier_private_key)
    try:
        result_validator.validate(deadline_outcome)
        _validate_semantics(deadline_outcome["subject"], deadline_outcome, index, trusted)
    except (HttpProbeContractError, ValidationError) as error:
        raise HttpProbeContractError(
            f"valid zero-attempt deadline outcome failed: {error}"
        ) from error

    semantic_mutations: list[tuple[str, dict[str, Any], dict[str, Any]]] = []
    missing_response = copy.deepcopy(result)
    missing_response["conditionRuns"][0]["attempts"][0]["backendResults"] = []
    _redigest_result(missing_response, verifier_private_key)
    semantic_mutations.append(
        ("missing backend response", missing_response["subject"], missing_response)
    )

    false_target_pass = copy.deepcopy(valid_target_outcomes[0][1])
    false_target_attempt = false_target_pass["conditionRuns"][0]["attempts"][0]
    false_target_attempt["targetErrorCode"] = None
    false_target_attempt["state"] = "pass"
    false_target_pass["conditionRuns"][0].update(
        {
            "achievedConsecutivePasses": 3,
            "state": "pass",
            "termination": "condition-satisfied",
        }
    )
    false_target_pass["pathConditionResults"][0] = {
        "id": "runtime.health",
        "state": "pass",
        "satisfied": True,
    }
    false_target_pass["aggregateState"] = "pass"
    false_target_pass["satisfied"] = True
    _redigest_result(false_target_pass, verifier_private_key)
    semantic_mutations.append(
        ("empty target classified pass", false_target_pass["subject"], false_target_pass)
    )

    network_snapshot = copy.deepcopy(result)
    target = network_snapshot["conditionRuns"][0]["attempts"][0]["preTarget"]
    target["networkPolicySetDigest"] = _digest("foreign-network-policy-set")
    _redigest_result(network_snapshot, verifier_private_key)
    semantic_mutations.append(
        ("untrusted NetworkPolicy snapshot", network_snapshot["subject"], network_snapshot)
    )

    broken_owner_chain = copy.deepcopy(result)
    owner_backend = broken_owner_chain["conditionRuns"][0]["attempts"][0][
        "preTarget"
    ]["backends"][0]
    owner_backend["replicaSetOwnerUid"] = "uid-other-deployment"
    _refresh_target_digests(
        broken_owner_chain["conditionRuns"][0]["attempts"][0]["preTarget"]
    )
    _redigest_result(broken_owner_chain, verifier_private_key)
    semantic_mutations.append(
        ("broken owner reference chain", broken_owner_chain["subject"], broken_owner_chain)
    )

    nullable_identity = copy.deepcopy(result)
    for snapshot_name in ("preTarget", "postTarget"):
        snapshot = nullable_identity["conditionRuns"][0]["attempts"][0][snapshot_name]
        nullable_backend = snapshot["backends"][0]
        for field in (
            "targetRefName",
            "podName",
            "podOwnerName",
            "replicaSetName",
            "podOwnerUid",
            "replicaSetUid",
            "replicaSetOwnerUid",
            "deploymentUid",
            "containerName",
        ):
            nullable_backend[field] = None
        _refresh_target_digests(snapshot)
    _redigest_result(nullable_identity, verifier_private_key)
    semantic_mutations.append(
        ("nullable owner identity pass", nullable_identity["subject"], nullable_identity)
    )

    invalid_runtime_image_id = copy.deepcopy(result)
    for snapshot_name in ("preTarget", "postTarget"):
        snapshot = invalid_runtime_image_id["conditionRuns"][0]["attempts"][0][
            snapshot_name
        ]
        image_backend = snapshot["backends"][0]
        image_backend["imageId"] = f"invalid/{image_backend['imageDigest']}"
        _refresh_target_digests(snapshot)
    _redigest_result(invalid_runtime_image_id, verifier_private_key)
    semantic_mutations.append(
        (
            "invalid runtime image ID pass",
            invalid_runtime_image_id["subject"],
            invalid_runtime_image_id,
        )
    )

    unsigned_result = copy.deepcopy(result)
    unsigned_result["verifier"]["signature"] = "A" * 86
    semantic_mutations.append(
        ("fabricated verifier signature", unsigned_result["subject"], unsigned_result)
    )

    cross_run = copy.deepcopy(result)
    cross_run["runId"] = "20000000-0000-4000-8000-000000000002"
    _redigest_result(cross_run, verifier_private_key)
    semantic_mutations.append(("cross-run replay", cross_run["subject"], cross_run))

    cross_work_order = copy.deepcopy(result)
    cross_work_order["workOrderId"] = "otherwork1"
    _redigest_result(cross_work_order, verifier_private_key)
    semantic_mutations.append(
        ("cross-WorkOrder replay", cross_work_order["subject"], cross_work_order)
    )

    changed_profile = copy.deepcopy(result)
    changed_profile["subject"]["probeProfile"]["digest"] = _digest("other-profile")
    _redigest_subject(changed_profile["subject"], subject_private_key)
    _redigest_result(changed_profile, verifier_private_key)
    semantic_mutations.append(
        ("changed probe profile", changed_profile["subject"], changed_profile)
    )

    changed_commit = copy.deepcopy(result)
    changed_commit["subject"]["platformCommitSha"] = "c" * 40
    _redigest_subject(changed_commit["subject"], subject_private_key)
    _redigest_result(changed_commit, verifier_private_key)
    semantic_mutations.append(
        ("untrusted platform commit", changed_commit["subject"], changed_commit)
    )

    duplicate_attempt = copy.deepcopy(result)
    duplicate_attempt["conditionRuns"][1]["attempts"][0]["attemptId"] = (
        duplicate_attempt["conditionRuns"][0]["attempts"][0]["attemptId"]
    )
    _redigest_result(duplicate_attempt, verifier_private_key)
    semantic_mutations.append(
        ("duplicate attempt", duplicate_attempt["subject"], duplicate_attempt)
    )

    no_attempt_delay = copy.deepcopy(result)
    first_attempt = no_attempt_delay["conditionRuns"][0]["attempts"][0]
    second_attempt = no_attempt_delay["conditionRuns"][0]["attempts"][1]
    second_attempt["startedAt"] = first_attempt["completedAt"]
    second_attempt["completedAt"] = _timestamp(
        _parse(second_attempt["startedAt"]) + timedelta(seconds=1)
    )
    _redigest_result(no_attempt_delay, verifier_private_key)
    semantic_mutations.append(
        ("missing PT1S attempt delay", no_attempt_delay["subject"], no_attempt_delay)
    )

    backend_deadline = copy.deepcopy(result)
    backend_deadline["conditionRuns"][0]["attempts"][0]["backendResults"][0][
        "durationMs"
    ] = 1500
    _redigest_result(backend_deadline, verifier_private_key)
    semantic_mutations.append(
        ("backend exceeds batch time", backend_deadline["subject"], backend_deadline)
    )

    service_drift = copy.deepcopy(result)
    service_drift["conditionRuns"][0]["attempts"][0]["postTarget"][
        "serviceResourceVersion"
    ] = "302"
    _redigest_result(service_drift, verifier_private_key)
    semantic_mutations.append(("Service drift", service_drift["subject"], service_drift))

    endpoint_drift = copy.deepcopy(result)
    endpoint_drift["conditionRuns"][0]["attempts"][0]["postTarget"][
        "endpointSliceSetDigest"
    ] = _digest("changed-slice")
    _redigest_result(endpoint_drift, verifier_private_key)
    semantic_mutations.append(("EndpointSlice drift", endpoint_drift["subject"], endpoint_drift))

    mixed_image = copy.deepcopy(result)
    mixed_image["conditionRuns"][0]["attempts"][0]["preTarget"]["backends"][0][
        "imageDigest"
    ] = f"sha256:{_digest('foreign-image')}"
    _redigest_result(mixed_image, verifier_private_key)
    semantic_mutations.append(("mixed backend image", mixed_image["subject"], mixed_image))

    false_batch = copy.deepcopy(result)
    backend = false_batch["conditionRuns"][0]["attempts"][0]["backendResults"][0]
    backend["status"] = 500
    backend["oracle"]["observedStatus"] = 500
    _redigest_result(false_batch, verifier_private_key)
    semantic_mutations.append(("forged passing batch", false_batch["subject"], false_batch))

    false_text_oracle = copy.deepcopy(result)
    text_backend = false_text_oracle["conditionRuns"][2]["attempts"][0][
        "backendResults"
    ][0]
    text_backend["oracle"]["observedByteDigest"] = _digest("other-body")
    _redigest_result(false_text_oracle, verifier_private_key)
    semantic_mutations.append(
        ("forged exact-text oracle", false_text_oracle["subject"], false_text_oracle)
    )

    false_json_oracle = copy.deepcopy(result)
    json_entry = false_json_oracle["conditionRuns"][3]["attempts"][0][
        "backendResults"
    ][0]["oracle"]["entries"][0]
    json_entry["observedPresent"] = False
    json_entry["observedType"] = None
    json_entry["observedValueDigest"] = None
    _redigest_result(false_json_oracle, verifier_private_key)
    semantic_mutations.append(
        ("forged JSON oracle", false_json_oracle["subject"], false_json_oracle)
    )

    false_streak = copy.deepcopy(result)
    interrupted = false_streak["conditionRuns"][0]["attempts"][1]
    interrupted_backend = interrupted["backendResults"][0]
    interrupted_backend["status"] = 500
    interrupted_backend["state"] = "fail"
    interrupted_backend["oracle"]["observedStatus"] = 500
    interrupted["state"] = "fail"
    _redigest_result(false_streak, verifier_private_key)
    semantic_mutations.append(
        ("non-pass did not reset streak", false_streak["subject"], false_streak)
    )

    only_two = copy.deepcopy(result)
    only_two["conditionRuns"][0]["attempts"].pop()
    only_two["conditionRuns"][0]["achievedConsecutivePasses"] = 2
    _redigest_result(only_two, verifier_private_key)
    semantic_mutations.append(("two passes marked complete", only_two["subject"], only_two))

    continued_after_success = copy.deepcopy(result)
    final_condition = continued_after_success["conditionRuns"][-1]
    fourth_attempt = copy.deepcopy(final_condition["attempts"][-1])
    fourth_attempt.update(
        {
            "attemptId": "0000000d-0000-4000-8000-00000000000d",
            "ordinal": 4,
            "startedAt": _timestamp(
                _parse(fourth_attempt["completedAt"]) + timedelta(seconds=1)
            ),
            "completedAt": _timestamp(
                _parse(fourth_attempt["completedAt"]) + timedelta(seconds=2)
            ),
            "targetErrorCode": "empty-backend-set",
            "backendResults": [],
            "state": "probe-error",
        }
    )
    fourth_attempt["preTarget"]["backends"] = []
    fourth_attempt["postTarget"]["backends"] = []
    _refresh_target_digests(fourth_attempt["preTarget"])
    _refresh_target_digests(fourth_attempt["postTarget"])
    final_condition["attempts"].append(fourth_attempt)
    continued_after_success["completedAt"] = fourth_attempt["completedAt"]
    _redigest_result(continued_after_success, verifier_private_key)
    semantic_mutations.append(
        (
            "condition continued after satisfaction",
            continued_after_success["subject"],
            continued_after_success,
        )
    )

    continued_after_deadline = copy.deepcopy(result)
    deadline_health = continued_after_deadline["conditionRuns"][0]
    deadline_attempt = deadline_health["attempts"][0]
    deadline_backend = deadline_attempt["backendResults"][0]
    deadline_backend["status"] = 500
    deadline_backend["oracle"]["observedStatus"] = 500
    deadline_backend["state"] = "fail"
    deadline_attempt["state"] = "fail"
    deadline_health.update(
        {
            "attempts": [deadline_attempt],
            "achievedConsecutivePasses": 0,
            "state": "fail",
            "termination": "run-deadline",
        }
    )
    continued_after_deadline["pathConditionResults"][0] = {
        "id": "runtime.health",
        "state": "fail",
        "satisfied": False,
    }
    continued_after_deadline["aggregateState"] = "fail"
    continued_after_deadline["satisfied"] = False
    continued_after_deadline["completedAt"] = continued_after_deadline["subject"][
        "deadline"
    ]
    _redigest_result(continued_after_deadline, verifier_private_key)
    semantic_mutations.append(
        (
            "attempts continued after run deadline",
            continued_after_deadline["subject"],
            continued_after_deadline,
        )
    )

    stale = copy.deepcopy(result)
    stale["subject"]["issuedAt"] = "2026-07-14T00:06:00Z"
    stale["subject"]["deadline"] = "2026-07-14T00:10:00Z"
    _redigest_subject(stale["subject"], subject_private_key)
    _redigest_result(stale, verifier_private_key)
    semantic_mutations.append(("stale delivery observation", stale["subject"], stale))

    attacker = copy.deepcopy(result)
    attacker["verifier"]["profileDigest"] = _digest("worker-profile")
    attacker["verifier"]["signingKeyId"] = "worker:self-signed"
    attacker_private_key = _private_key("attacker")
    _redigest_result(attacker, attacker_private_key)
    semantic_mutations.append(("worker-signed evidence", attacker["subject"], attacker))

    expired = copy.deepcopy(result)
    expired["expiresAt"] = expired["completedAt"]
    _redigest_result(expired, verifier_private_key)
    semantic_mutations.append(("expired evidence", expired["subject"], expired))

    reordered = copy.deepcopy(result)
    reordered["conditionRuns"][0], reordered["conditionRuns"][1] = (
        reordered["conditionRuns"][1],
        reordered["conditionRuns"][0],
    )
    _redigest_result(reordered, verifier_private_key)
    semantic_mutations.append(("reordered conditions", reordered["subject"], reordered))

    for name, mutated_subject, mutated_result in semantic_mutations:
        try:
            subject_validator.validate(mutated_subject)
            result_validator.validate(mutated_result)
            _validate_semantics(mutated_subject, mutated_result, index, trusted)
        except (HttpProbeContractError, ValidationError):
            continue
        raise HttpProbeContractError(f"invalid HTTP semantic mutation passed: {name}")
