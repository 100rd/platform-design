#!/usr/bin/env python3
"""Validate the indexed darkfactory platform-contract bundle."""

from __future__ import annotations

import copy
import hashlib
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import yaml
from jsonschema import Draft202012Validator, FormatChecker, ValidationError
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_ROOT = ROOT / "platform-contracts"
INDEX_PATH = CONTRACT_ROOT / "index.yaml"
FORMAT_CHECKER = FormatChecker()


@FORMAT_CHECKER.checks("date-time", raises=(TypeError, ValueError))
def is_timezone_aware_datetime(value: object) -> bool:
    if not isinstance(value, str) or "T" not in value:
        return False
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return parsed.tzinfo is not None


@FORMAT_CHECKER.checks("uri", raises=(TypeError, ValueError))
def is_absolute_uri(value: object) -> bool:
    if not isinstance(value, str):
        return False
    return bool(urlsplit(value).scheme)


class ContractError(Exception):
    pass


def load_yaml(path: Path) -> Any:
    with path.open(encoding="utf-8") as stream:
        return yaml.safe_load(stream)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_keys(value: dict[str, Any], expected: set[str], context: str) -> None:
    actual = set(value)
    if actual != expected:
        raise ContractError(
            f"{context}: expected keys {sorted(expected)}, got {sorted(actual)}"
        )


def artifact_id(document: dict[str, Any]) -> str:
    metadata = document["metadata"]
    return f"{metadata['name']}/{metadata['version']}"


def validate_index(index: dict[str, Any]) -> list[dict[str, str]]:
    require_keys(index, {"apiVersion", "kind", "metadata", "spec"}, "index")
    if index["apiVersion"] != "platform/contracts-index/v1":
        raise ContractError("index: unsupported apiVersion")
    if index["kind"] != "PlatformContractIndex":
        raise ContractError("index: unsupported kind")
    require_keys(index["metadata"], {"owner", "version"}, "index.metadata")
    require_keys(
        index["spec"],
        {"digestAlgorithm", "bundleDigest", "artifacts", "registries"},
        "index.spec",
    )
    if index["spec"]["digestAlgorithm"] != "sha256-path-nul-bytes-v1":
        raise ContractError("index: unsupported digest algorithm")
    artifacts = index["spec"]["artifacts"]
    if not isinstance(artifacts, list) or not artifacts:
        raise ContractError("index: artifacts must be a non-empty list")
    for position, artifact in enumerate(artifacts):
        require_keys(artifact, {"path", "kind", "schema", "sha256"}, f"artifact[{position}]")
    paths = [artifact["path"] for artifact in artifacts]
    if paths != sorted(paths) or len(paths) != len(set(paths)):
        raise ContractError("index: artifact paths must be unique and lexically sorted")
    authoritative_roots = (
        "schemas",
        "products",
        "entity-classes",
        "realms",
        "delivery-profiles",
        "paths",
    )
    discovered = sorted(
        path.relative_to(CONTRACT_ROOT).as_posix()
        for root in authoritative_roots
        for path in (CONTRACT_ROOT / root).rglob("*")
        if path.is_file() and path.suffix in {".json", ".yaml", ".yml"}
    )
    if paths != discovered:
        raise ContractError(
            "index: authoritative files and indexed artifacts differ: "
            f"indexed={paths}, discovered={discovered}"
        )
    digest_pattern = re.compile(r"^[0-9a-f]{64}$")
    if not digest_pattern.fullmatch(index["spec"]["bundleDigest"]):
        raise ContractError("index: bundleDigest must be a lowercase SHA-256")
    allowed_kinds = {
        "Schema",
        "PlatformProduct",
        "EntityClass",
        "Realm",
        "PlatformDeliveryProfile",
        "PlatformPath",
    }
    for position, artifact in enumerate(artifacts):
        if artifact["kind"] not in allowed_kinds:
            raise ContractError(f"artifact[{position}]: unsupported kind {artifact['kind']}")
        if not digest_pattern.fullmatch(artifact["sha256"]):
            raise ContractError(f"artifact[{position}]: sha256 must be a lowercase SHA-256")
    require_keys(
        index["spec"]["registries"],
        {"actions", "capabilities", "evidenceTypes", "policies", "probes"},
        "index.spec.registries",
    )
    for name, identifiers in index["spec"]["registries"].items():
        if identifiers != sorted(set(identifiers)):
            raise ContractError(f"registry {name}: identifiers must be unique and sorted")
    return artifacts


def validate_digests(index: dict[str, Any], artifacts: list[dict[str, str]]) -> None:
    bundle = hashlib.sha256()
    for artifact in artifacts:
        relative = Path(artifact["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ContractError(f"unsafe artifact path: {relative}")
        path = CONTRACT_ROOT / relative
        if not path.is_file():
            raise ContractError(f"missing indexed artifact: {relative}")
        actual = sha256(path)
        if actual != artifact["sha256"]:
            raise ContractError(
                f"digest mismatch for {relative}: index={artifact['sha256']} actual={actual}"
            )
        bundle.update(relative.as_posix().encode("utf-8"))
        bundle.update(b"\0")
        bundle.update(path.read_bytes())
    actual_bundle = bundle.hexdigest()
    if actual_bundle != index["spec"]["bundleDigest"]:
        raise ContractError(
            f"bundle digest mismatch: index={index['spec']['bundleDigest']} actual={actual_bundle}"
        )


def load_and_validate_artifacts(
    artifacts: list[dict[str, str]],
) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    schemas: dict[str, Any] = {}
    documents: dict[str, dict[str, Any]] = {}
    for artifact in artifacts:
        path = CONTRACT_ROOT / artifact["path"]
        document = load_yaml(path)
        if artifact["kind"] == "Schema":
            Draft202012Validator.check_schema(document)
            schema_id = document.get("$id")
            if not schema_id or schema_id in schemas:
                raise ContractError(f"schema {path}: missing or duplicate $id")
            schemas[schema_id] = document
        else:
            if document.get("kind") != artifact["kind"]:
                raise ContractError(
                    f"{artifact['path']}: index kind {artifact['kind']} "
                    f"does not match document kind {document.get('kind')}"
                )
            documents[artifact["path"]] = document

    registry = Registry().with_resources(
        (schema_id, Resource.from_contents(schema))
        for schema_id, schema in schemas.items()
    )
    for artifact in artifacts:
        if artifact["kind"] == "Schema":
            continue
        schema_id = artifact["schema"]
        if schema_id not in schemas:
            raise ContractError(f"{artifact['path']}: unknown schema {schema_id}")
        validator = Draft202012Validator(
            schemas[schema_id], registry=registry, format_checker=FORMAT_CHECKER
        )
        errors = sorted(validator.iter_errors(documents[artifact["path"]]), key=lambda e: list(e.path))
        if errors:
            raise ContractError(f"{artifact['path']}: {errors[0].message}")
    return schemas, documents


def require_registered(value: str, registry: set[str], context: str) -> None:
    if value not in registry:
        raise ContractError(f"{context}: unregistered identifier {value}")


def template_fields(value: str, context: str) -> set[str]:
    fields = set(re.findall(r"\{([^{}]+)\}", value))
    residue = re.sub(r"\{[^{}]+\}", "", value)
    if "{" in residue or "}" in residue:
        raise ContractError(f"{context}: malformed template")
    return fields


def validate_observer_access(
    observer: dict[str, Any],
    registries: dict[str, set[str]],
    context: str,
) -> None:
    credential = observer["credential"]
    attestation = observer["attestation"]
    cleanup = observer["cleanup"]
    for action in (
        credential["issueAction"],
        attestation["action"],
        cleanup["revokeAction"],
        cleanup["reaperAction"],
    ):
        require_registered(action, registries["actions"], context)
    for probe in (
        attestation["probe"],
        attestation["semanticVerifier"],
        credential["scopeSemanticVerifier"],
        cleanup["verifier"],
    ):
        require_registered(probe, registries["probes"], context)
    for evidence_type in (
        attestation["evidenceType"],
        attestation["inheritedAuthorityEvidenceType"],
        cleanup["evidenceType"],
    ):
        require_registered(evidence_type, registries["evidenceTypes"], context)

    templates = (
        observer["serviceAccount"]["nameTemplate"],
        observer["applicationRole"]["nameTemplate"],
        observer["applicationRoleBinding"]["nameTemplate"],
        observer["namespaceClusterRole"]["nameTemplate"],
        observer["namespaceClusterRoleBinding"]["nameTemplate"],
        observer["realmRoleBinding"]["nameTemplate"],
    )
    for value in templates:
        if template_fields(value, context) != {"workOrderId"}:
            raise ContractError(f"{context}: observer object name is not WorkOrder-derived")
        if len(value.replace("{workOrderId}", "x" * 53)) > 63:
            raise ContractError(f"{context}: observer object name can exceed Kubernetes limits")

    rules = (
        observer["applicationRole"]["rules"]
        + observer["namespaceClusterRole"]["rules"]
        + observer["inventoryClusterRole"]["rules"]
    )
    for rule in rules:
        if "nonResourceURLs" in rule:
            raise ContractError(f"{context}: platform observer rules cannot grant non-resource URLs")
        values = rule.get("apiGroups", []) + rule.get("resources", []) + rule.get("verbs", [])
        if "*" in values:
            raise ContractError(f"{context}: platform observer rules cannot contain wildcards")
        if set(rule["verbs"]) - {"get", "list"}:
            raise ContractError(f"{context}: platform observer rules contain mutation or watch")

    inventory_rules = observer["inventoryClusterRole"]["rules"]
    actual_inventory = {
        (api_group, resource, verb)
        for rule in inventory_rules
        for api_group in rule["apiGroups"]
        for resource in rule["resources"]
        for verb in rule["verbs"]
    }
    expected_inventory = {
        ("", resource, "list")
        for resource in (
            "persistentvolumeclaims",
            "pods",
            "resourcequotas",
            "serviceaccounts",
            "services",
        )
    } | {
        ("apps", resource, "list") for resource in ("deployments", "replicasets")
    } | {
        ("networking.k8s.io", resource, "list")
        for resource in ("ingresses", "networkpolicies")
    } | {
        ("rbac.authorization.k8s.io", resource, "list")
        for resource in ("rolebindings", "roles")
    }
    if actual_inventory != expected_inventory:
        raise ContractError(f"{context}: observer inventory rules differ from the closed 11-kind set")
    if observer["inventoryClusterRole"]["name"] != "darkfactory-preview-delivery-list-v1":
        raise ContractError(f"{context}: shared observer role is not immutable and versioned")

    expected_negative_cases = {
        "appproject-get": {
            "id": "appproject-get", "verbs": ["get"], "apiGroup": "argoproj.io",
            "resource": "appprojects", "subresource": "",
            "scopeFrom": "application.namespace", "namesFrom": ["application.project"],
        },
        "configmap-get": {
            "id": "configmap-get", "verbs": ["get"], "apiGroup": "",
            "resource": "configmaps", "subresource": "",
            "scopeFrom": "destination.namespaceTemplate",
            "namesFrom": ["policy.anyConfigMap"],
        },
        "configmap-list": {
            "id": "configmap-list", "verbs": ["list"], "apiGroup": "",
            "resource": "configmaps", "subresource": "",
            "scopeFrom": "destination.namespaceTemplate", "namesFrom": [],
        },
        "foreign-application-get": {
            "id": "foreign-application-get", "verbs": ["get"], "apiGroup": "argoproj.io",
            "resource": "applications", "subresource": "",
            "scopeFrom": "application.namespace", "namesFrom": ["policy.foreignApplication"],
        },
        "foreign-namespace-get": {
            "id": "foreign-namespace-get", "verbs": ["get"], "apiGroup": "",
            "resource": "namespaces", "subresource": "", "scopeFrom": "cluster",
            "namesFrom": ["policy.foreignNamespace"],
        },
        "foreign-tokenrequest-create": {
            "id": "foreign-tokenrequest-create", "verbs": ["create"],
            "apiGroup": "", "resource": "serviceaccounts", "subresource": "token",
            "scopeFrom": "observerAccess.observerNamespace",
            "namesFrom": ["policy.foreignServiceAccount"],
        },
        "impersonate-groups": {
            "id": "impersonate-groups", "verbs": ["impersonate"],
            "apiGroup": "", "resource": "groups", "subresource": "",
            "scopeFrom": "cluster", "namesFrom": ["policy.anyIdentity"],
        },
        "impersonate-serviceaccounts": {
            "id": "impersonate-serviceaccounts", "verbs": ["impersonate"],
            "apiGroup": "", "resource": "serviceaccounts", "subresource": "",
            "scopeFrom": "cluster", "namesFrom": ["policy.anyIdentity"],
        },
        "impersonate-userextras-scopes": {
            "id": "impersonate-userextras-scopes", "verbs": ["impersonate"],
            "apiGroup": "authentication.k8s.io", "resource": "userextras",
            "subresource": "scopes", "scopeFrom": "cluster",
            "namesFrom": ["policy.anyIdentity"],
        },
        "impersonate-users": {
            "id": "impersonate-users", "verbs": ["impersonate"],
            "apiGroup": "", "resource": "users", "subresource": "",
            "scopeFrom": "cluster", "namesFrom": ["policy.anyIdentity"],
        },
        "pod-exec-create": {
            "id": "pod-exec-create", "verbs": ["create"], "apiGroup": "",
            "resource": "pods", "subresource": "exec",
            "scopeFrom": "destination.namespaceTemplate", "namesFrom": ["policy.anyPod"],
        },
        "pod-log-get": {
            "id": "pod-log-get", "verbs": ["get"], "apiGroup": "", "resource": "pods",
            "subresource": "log", "scopeFrom": "destination.namespaceTemplate",
            "namesFrom": ["policy.anyPod"],
        },
        "pod-portforward-create": {
            "id": "pod-portforward-create", "verbs": ["create"], "apiGroup": "",
            "resource": "pods", "subresource": "portforward",
            "scopeFrom": "destination.namespaceTemplate", "namesFrom": ["policy.anyPod"],
        },
        "secret-list": {
            "id": "secret-list", "verbs": ["list"], "apiGroup": "", "resource": "secrets",
            "subresource": "", "scopeFrom": "destination.namespaceTemplate", "namesFrom": [],
        },
        "secret-get": {
            "id": "secret-get", "verbs": ["get"], "apiGroup": "",
            "resource": "secrets", "subresource": "",
            "scopeFrom": "destination.namespaceTemplate",
            "namesFrom": ["policy.anySecret"],
        },
        "service-proxy-get": {
            "id": "service-proxy-get", "verbs": ["get"], "apiGroup": "",
            "resource": "services", "subresource": "proxy",
            "scopeFrom": "destination.namespaceTemplate", "namesFrom": ["policy.anyService"],
        },
        "tokenrequest-create": {
            "id": "tokenrequest-create", "verbs": ["create"], "apiGroup": "",
            "resource": "serviceaccounts", "subresource": "token",
            "scopeFrom": "observerAccess.observerNamespace",
            "namesFrom": ["observerAccess.serviceAccount.nameTemplate"],
        },
        "foreign-realm-list": {
            "id": "foreign-realm-list", "verbs": ["list"],
            "resourcesFrom": "observerAccess.credential.kindIds",
            "scopeFrom": "policy.foreignRealm",
        },
        "declared-resource-mutations": {
            "id": "declared-resource-mutations",
            "verbs": ["create", "delete", "deletecollection", "patch", "update"],
            "resourcesFrom": "policy.workloadAndControlKindIds",
            "scopeFrom": "policy.declaredScopes",
        },
        "inventory-watch": {
            "id": "inventory-watch", "verbs": ["watch"],
            "resourcesFrom": "observerAccess.credential.kindIds",
            "scopeFrom": "destination.namespaceTemplate",
        },
        "sensitive-resource-watch": {
            "id": "sensitive-resource-watch", "verbs": ["watch"],
            "resourcesFrom": "policy.sensitiveKindIds",
            "scopeFrom": "destination.namespaceTemplate",
        },
    }
    negative_cases = attestation["negativeAuthorizationCases"]
    actual_negative_cases = {case["id"]: case for case in negative_cases}
    if len(actual_negative_cases) != len(negative_cases):
        raise ContractError(f"{context}: duplicate negative authorization case")
    if actual_negative_cases != expected_negative_cases:
        raise ContractError(f"{context}: negative authorization matrix differs from the closed profile")

    if observer["workerAuthorable"] or observer["authority"] != "platform-control-plane":
        raise ContractError(f"{context}: observer control inventory is worker-authorable")
    if attestation["platformRulesAllowNonResourceUrls"]:
        raise ContractError(f"{context}: observer profile permits platform discovery rules")
    if attestation["discoveryTransportOperation"]:
        raise ContractError(f"{context}: observer transport exposes discovery")
    if not cleanup["registerBeforeCreate"]:
        raise ContractError(f"{context}: observer cleanup is not registered before mutation")


def validate_delivery_profile(
    profile: dict[str, Any],
    registries: dict[str, set[str]],
    context: str,
) -> None:
    require_registered(profile["mechanism"], registries["capabilities"], context)
    expected_template_bindings = {
        "workOrderIdFrom": "workOrder.id",
        "serviceNameFrom": "request.inputs.serviceName",
        "realmNameFrom": "realm.effectiveName",
    }
    if profile["templateBindings"] != expected_template_bindings:
        raise ContractError(f"{context}: template identities are not authority-bound")
    repository_policy = profile["source"]["repositoryAuthorization"]["policy"]
    require_registered(repository_policy, registries["policies"], context)
    observations = profile["observations"]
    require_registered(observations["action"], registries["actions"], context)
    require_registered(observations["gitopsProbe"], registries["probes"], context)
    require_registered(observations["gitopsEvidenceType"], registries["evidenceTypes"], context)
    require_registered(observations["realmProbe"], registries["probes"], context)
    require_registered(observations["realmEvidenceType"], registries["evidenceTypes"], context)
    if profile["schemaVersion"] == "platform/delivery-profile/v2":
        require_registered(observations["semanticVerifier"], registries["probes"], context)
    compensation = profile["compensation"]
    require_registered(compensation["action"], registries["actions"], context)
    require_registered(compensation["verifier"], registries["probes"], context)
    require_registered(compensation["evidenceType"], registries["evidenceTypes"], context)

    source_fields = template_fields(
        profile["source"]["gitopsPathTemplate"], f"{context}.source.gitopsPathTemplate"
    )
    if source_fields != {"serviceName", "workOrderId"}:
        raise ContractError(
            f"{context}: GitOps path template must use the trusted serviceName and workOrderId fields"
        )
    labels = profile["application"]["requiredLabels"]
    required_label_values = {
        "darkfactory.platform/path": profile["path"].replace("/", "-"),
        "darkfactory.platform/realm": "{realmName}",
        "darkfactory.platform/work-order": "{workOrderId}",
    }
    if labels != required_label_values:
        raise ContractError(f"{context}: required ownership labels differ from the closed binding")

    envelope = profile["resourceEnvelope"]
    required_kinds = set(envelope["requiredKinds"])
    allowed_kinds = set(envelope["allowedKinds"])
    expected_kinds = {
        "apps/v1/Deployment",
        "networking.k8s.io/v1/Ingress",
        "networking.k8s.io/v1/NetworkPolicy",
        "v1/Namespace",
        "v1/ResourceQuota",
        "v1/Service",
    }
    if required_kinds != expected_kinds or allowed_kinds != expected_kinds:
        raise ContractError(f"{context}: resource kinds differ from the closed P0 envelope")
    expected_cluster_binding = [
        {
            "kind": "v1/Namespace",
            "nameFrom": "destination.namespaceTemplate",
            "maxCount": 1,
        }
    ]
    if envelope["clusterScopedBindings"] != expected_cluster_binding:
        raise ContractError(f"{context}: cluster-scoped binding is not the one derived Namespace")
    if envelope["requiredKinds"] != sorted(envelope["requiredKinds"]):
        raise ContractError(f"{context}: requiredKinds must be sorted")
    if envelope["allowedKinds"] != sorted(envelope["allowedKinds"]):
        raise ContractError(f"{context}: allowedKinds must be sorted")
    required_assertions = {
        "dedicated-namespace",
        "default-deny-network",
        "digest-pinned-image",
        "no-cross-realm-rbac",
        "no-persistent-volumes",
        "no-runtime-secrets",
        "no-service-account-token",
        "quota-bound",
    }
    if profile["schemaVersion"] == "platform/delivery-profile/v2":
        required_assertions.remove("no-cross-realm-rbac")
        required_assertions.add("no-workload-rbac")
    if set(envelope["requiredAssertions"]) != required_assertions:
        raise ContractError(f"{context}: preview containment assertions are incomplete")
    if envelope["requiredAssertions"] != sorted(envelope["requiredAssertions"]):
        raise ContractError(f"{context}: requiredAssertions must be sorted")
    if profile["schemaVersion"] == "platform/delivery-profile/v2":
        validate_observer_access(profile["observerAccess"], registries, context)
        if compensation["action"] != "delivery.revert-prune-and-revoke-preview/v2":
            raise ContractError(f"{context}: observer access is absent from compensation")
        if compensation["verifier"] != "realm.preview-and-observer-pruned/v1":
            raise ContractError(f"{context}: observer cleanup is absent from compensation verification")
    expected_compensation_scope = {
        "repositoryFrom": "source.repositoryFrom",
        "gitopsPathFrom": "source.gitopsPathTemplate",
        "applicationNameFrom": "application.nameTemplate",
        "destinationNamespaceFrom": "destination.namespaceTemplate",
        "inventoryDigestFrom": "source.desiredInventoryFrom",
        "ownershipLabelFrom": "resourceEnvelope.ownershipLabel",
        "ownershipValueFrom": "resourceEnvelope.ownershipValueFrom",
    }
    if profile["schemaVersion"] == "platform/delivery-profile/v2":
        expected_compensation_scope.update(
            {
                "observerAccessInventoryFrom": "observerAccess.desiredInventoryFrom",
                "observerAccessSubjectFrom": "observerAccess.serviceAccount.nameTemplate",
            }
        )
    if compensation["scope"] != expected_compensation_scope:
        raise ContractError(f"{context}: compensation scope is not identity-bound")


def validate_semantics(
    index: dict[str, Any], schemas: dict[str, Any], documents: dict[str, dict[str, Any]]
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any]]:
    products: dict[str, Any] = {}
    entities: dict[str, Any] = {}
    realms: dict[str, Any] = {}
    delivery_profiles: dict[str, Any] = {}
    paths: dict[str, Any] = {}
    for document in documents.values():
        kind = document.get("kind")
        identifier = artifact_id(document)
        if kind == "PlatformProduct":
            target = products
        elif kind == "EntityClass":
            target = entities
        elif kind == "Realm":
            target = realms
        elif kind == "PlatformDeliveryProfile":
            target = delivery_profiles
        elif kind == "PlatformPath":
            target = paths
        else:
            raise ContractError(f"unsupported document kind {kind}")
        if identifier in target:
            raise ContractError(f"duplicate {kind} identifier {identifier}")
        target[identifier] = document

    registries = {name: set(values) for name, values in index["spec"]["registries"].items()}
    for profile_id, profile in delivery_profiles.items():
        validate_delivery_profile(profile, registries, profile_id)
    for entity_id, entity in entities.items():
        for capability in entity["requiredCapabilities"]:
            require_registered(capability, registries["capabilities"], entity_id)
        for probe in entity["probes"]:
            require_registered(probe["id"], registries["probes"], entity_id)
        require_registered(entity["compensation"]["action"], registries["actions"], entity_id)
        require_registered(entity["compensation"]["verifier"], registries["probes"], entity_id)
        for realm_id in entity["allowedRealms"]:
            if realm_id not in realms:
                raise ContractError(f"{entity_id}: unknown Realm {realm_id}")

    for realm_id, realm in realms.items():
        require_registered(realm["resolution"]["derivedBy"], registries["actions"], realm_id)
        for policy in realm["policyRefs"]:
            require_registered(policy, registries["policies"], realm_id)

    for product_id, product in products.items():
        for path_id in product["paths"]:
            if path_id not in paths:
                raise ContractError(f"{product_id}: publishes unknown path {path_id}")

    for realm_id, realm in realms.items():
        for path_id in realm["admission"]["paths"]:
            if path_id not in paths:
                raise ContractError(f"{realm_id}: admits unknown path {path_id}")

    for path_id, path in paths.items():
        if path["product"] not in products:
            raise ContractError(f"{path_id}: unknown product {path['product']}")
        if path_id not in products[path["product"]]["paths"]:
            raise ContractError(f"{path_id}: product does not publish path")
        if products[path["product"]]["metadata"]["lifecycle"] != path["metadata"]["state"]:
            raise ContractError(f"{path_id}: product lifecycle does not match path")
        if path["inputSchema"] not in schemas:
            raise ContractError(f"{path_id}: unknown input schema {path['inputSchema']}")
        profile_id = path.get("deliveryProfile")
        profile = None
        if path["schemaVersion"] == "platform/path/v2":
            if not profile_id:
                raise ContractError(f"{path_id}: v2 delivery profile is required")
            if profile_id not in delivery_profiles:
                raise ContractError(f"{path_id}: unknown delivery profile {profile_id}")
            profile = delivery_profiles[profile_id]
            if profile["path"] != path_id:
                raise ContractError(f"{path_id}: delivery profile is bound to {profile['path']}")
            if profile["metadata"]["state"] != path["metadata"]["state"]:
                raise ContractError(f"{path_id}: delivery profile lifecycle does not match path")
            repository_policy = profile["source"]["repositoryAuthorization"]["policy"]
            if repository_policy not in path["policies"]:
                raise ContractError(f"{path_id}: repository authorization policy is absent")
        elif path["schemaVersion"] == "platform/path/v1":
            if profile_id:
                raise ContractError(f"{path_id}: v1 path cannot bind a v2 delivery profile")
        else:
            raise ContractError(f"{path_id}: unsupported path schema version")
        for entity_id in path["entityClasses"]:
            if entity_id not in entities:
                raise ContractError(f"{path_id}: unknown EntityClass {entity_id}")
            if entities[entity_id]["metadata"]["state"] != path["metadata"]["state"]:
                raise ContractError(f"{path_id}: EntityClass lifecycle does not match path")
            missing_realms = set(path["supportedRealms"]) - set(entities[entity_id]["allowedRealms"])
            if missing_realms:
                raise ContractError(
                    f"{path_id}: EntityClass {entity_id} excludes Realms {sorted(missing_realms)}"
                )
        if profile:
            if not any(
                profile["mechanism"] in entities[entity_id]["requiredCapabilities"]
                for entity_id in path["entityClasses"]
            ):
                raise ContractError(f"{path_id}: no EntityClass requires the delivery mechanism")
            step_actions = {step["id"]: step["action"] for step in path["workflow"]}
            required_source_steps = {
                "await-human-merge": "delivery.await-human-merge/v1",
                "validate-change": "verification.run-source-gates/v1",
            }
            for step_id, action in required_source_steps.items():
                if step_actions.get(step_id) != action:
                    raise ContractError(
                        f"{path_id}: delivery source binding requires {step_id} -> {action}"
                    )
            if profile["schemaVersion"] == "platform/delivery-profile/v2":
                observer = profile["observerAccess"]
                referenced_runtime_schemas = {
                    profile["observations"]["scopeSchema"],
                    profile["observations"]["snapshotSchema"],
                    profile["observations"]["evidenceSchema"],
                    observer["credential"]["scopeSchema"],
                    observer["attestation"]["schema"],
                    observer["cleanup"]["evidenceSchema"],
                }
                unknown_runtime_schemas = referenced_runtime_schemas - set(schemas)
                if unknown_runtime_schemas:
                    raise ContractError(
                        f"{path_id}: observer runtime schemas are unregistered: "
                        f"{sorted(unknown_runtime_schemas)}"
                    )
                required_observer_steps = {
                    "attest-observer-access": "delivery.attest-observer-access/v1",
                    "issue-observer-credential": "delivery.issue-observer-credential/v1",
                    "observe-gitops": "delivery.observe-argocd-sync/v2",
                    "provision-observer-access": "delivery.provision-observer-access/v1",
                    "register-observer-access-compensation": "execution.register-compensation/v1",
                    "revoke-observer-access": "delivery.revoke-observer-access/v1",
                    "store-observation-evidence": "evidence.store-delivery-observation/v1",
                }
                for step_id, action in required_observer_steps.items():
                    if step_actions.get(step_id) != action:
                        raise ContractError(
                            f"{path_id}: observer access requires {step_id} -> {action}"
                        )
                step_needs = {step["id"]: step["needs"] for step in path["workflow"]}
                observer_chain = {
                    "register-observer-access-compensation": ["await-human-merge"],
                    "provision-observer-access": ["register-observer-access-compensation"],
                    "attest-observer-access": ["provision-observer-access"],
                    "issue-observer-credential": ["attest-observer-access"],
                    "observe-gitops": ["issue-observer-credential"],
                    "store-observation-evidence": ["observe-gitops"],
                    "revoke-observer-access": ["store-observation-evidence"],
                    "verify-runtime": ["revoke-observer-access"],
                }
                for step_id, needs in observer_chain.items():
                    if step_needs.get(step_id) != needs:
                        raise ContractError(
                            f"{path_id}: observer lifecycle ordering is not closed at {step_id}"
                        )
                if "delivery.platform-observer-access/v1" not in path["policies"]:
                    raise ContractError(f"{path_id}: observer access policy is absent")
        for realm_id in path["supportedRealms"]:
            if realm_id not in realms:
                raise ContractError(f"{path_id}: unknown Realm {realm_id}")
            realm = realms[realm_id]
            if path["metadata"]["state"] == "draft":
                if path_id in realm["admission"]["paths"]:
                    raise ContractError(f"{path_id}: draft path cannot be admitted by {realm_id}")
            else:
                if path_id not in realm["admission"]["paths"]:
                    raise ContractError(f"{path_id}: Realm {realm_id} does not admit path")
                if path["metadata"]["state"] not in realm["admission"]["pathStates"]:
                    raise ContractError(f"{path_id}: Realm {realm_id} does not admit path state")
        step_ids = [step["id"] for step in path["workflow"]]
        if len(step_ids) != len(set(step_ids)):
            raise ContractError(f"{path_id}: duplicate workflow step id")
        seen: set[str] = set()
        for step in path["workflow"]:
            require_registered(step["action"], registries["actions"], path_id)
            unknown_needs = set(step["needs"]) - seen
            if unknown_needs:
                raise ContractError(f"{path_id}: step {step['id']} has non-prior needs {sorted(unknown_needs)}")
            seen.add(step["id"])
        for policy in path["policies"]:
            require_registered(policy, registries["policies"], path_id)
        for condition in path["conditionsOfDone"]:
            require_registered(condition["probe"], registries["probes"], path_id)
            require_registered(condition["evidenceType"], registries["evidenceTypes"], path_id)
        condition_pairs = {
            (condition["probe"], condition["evidenceType"])
            for condition in path["conditionsOfDone"]
        }
        if profile:
            observations = profile["observations"]
            if (
                observations["gitopsProbe"],
                observations["gitopsEvidenceType"],
            ) not in condition_pairs:
                raise ContractError(
                    f"{path_id}: delivery profile GitOps observation is not a Condition of Done"
                )
            if (
                observations["realmProbe"],
                observations["realmEvidenceType"],
            ) not in condition_pairs:
                raise ContractError(
                    f"{path_id}: delivery profile Realm observation is not a Condition of Done"
                )
            if observations["action"] not in {
                step["action"] for step in path["workflow"]
            }:
                raise ContractError(
                    f"{path_id}: delivery profile observation action is absent from workflow"
                )
            if profile["schemaVersion"] == "platform/delivery-profile/v2":
                observer = profile["observerAccess"]
                required_observer_pairs = {
                    (observer["attestation"]["probe"], observer["attestation"]["evidenceType"]),
                    (observer["cleanup"]["verifier"], observer["cleanup"]["evidenceType"]),
                }
                if not required_observer_pairs.issubset(condition_pairs):
                    raise ContractError(
                        f"{path_id}: observer authority or cleanup is not a Condition of Done"
                    )
        condition_ids = [condition["id"] for condition in path["conditionsOfDone"]]
        if len(condition_ids) != len(set(condition_ids)):
            raise ContractError(f"{path_id}: duplicate Condition of Done id")
        require_registered(path["compensation"]["action"], registries["actions"], path_id)
        require_registered(path["compensation"]["verifier"], registries["probes"], path_id)
        if profile:
            if profile["compensation"]["action"] != path["compensation"]["action"]:
                raise ContractError(f"{path_id}: delivery profile compensation action mismatch")
            if profile["compensation"]["verifier"] != path["compensation"]["verifier"]:
                raise ContractError(
                    f"{path_id}: delivery profile compensation verifier mismatch"
                )
            if (
                profile["compensation"]["evidenceType"]
                not in path["evidence"]["requiredTypes"]
            ):
                raise ContractError(
                    f"{path_id}: delivery profile compensation evidence is not required"
                )
            if profile["schemaVersion"] == "platform/delivery-profile/v2":
                observer = profile["observerAccess"]
                required_observer_evidence = {
                    observer["attestation"]["evidenceType"],
                    observer["attestation"]["inheritedAuthorityEvidenceType"],
                    observer["cleanup"]["evidenceType"],
                    observations["realmEvidenceType"],
                }
                missing_evidence = required_observer_evidence - set(path["evidence"]["requiredTypes"])
                if missing_evidence:
                    raise ContractError(
                        f"{path_id}: observer evidence is incomplete: {sorted(missing_evidence)}"
                    )
        if "supply-chain.attestation/v1" not in path["evidence"]["requiredTypes"]:
            raise ContractError(f"{path_id}: attested image evidence is not required")
        for evidence_type in path["evidence"]["requiredTypes"]:
            require_registered(evidence_type, registries["evidenceTypes"], path_id)
    referenced_profiles = {
        path["deliveryProfile"] for path in paths.values() if path.get("deliveryProfile")
    }
    orphaned_profiles = set(delivery_profiles) - referenced_profiles
    if orphaned_profiles:
        raise ContractError(f"orphaned delivery profiles: {sorted(orphaned_profiles)}")
    return products, paths, realms, delivery_profiles


def validate_request(
    request: dict[str, Any],
    schemas: dict[str, Any],
    products: dict[str, Any],
    paths: dict[str, Any],
    realms: dict[str, Any],
) -> None:
    Draft202012Validator(
        schemas["urn:darkfactory:platform-contract:product-request:v1"],
        format_checker=FORMAT_CHECKER,
    ).validate(request)
    product_id = request["product"]
    path_id = request["path"]
    realm_id = request["realmClass"]
    if product_id not in products:
        raise ContractError(f"request: unknown product {product_id}")
    if path_id not in paths or path_id not in products[product_id]["paths"]:
        raise ContractError(f"request: path {path_id} is not published by {product_id}")
    path = paths[path_id]
    if path["product"] != product_id:
        raise ContractError("request: product/path mismatch")
    if realm_id not in realms or realm_id not in path["supportedRealms"]:
        raise ContractError(f"request: unsupported Realm {realm_id}")
    realm = realms[realm_id]
    if path_id not in realm["admission"]["paths"]:
        raise ContractError(f"request: Realm {realm_id} does not admit {path_id}")
    Draft202012Validator(
        schemas[path["inputSchema"]], format_checker=FORMAT_CHECKER
    ).validate(request["inputs"])


def validate_fixtures(
    schemas: dict[str, Any],
    products: dict[str, Any],
    paths: dict[str, Any],
    realms: dict[str, Any],
) -> None:
    valid = sorted((CONTRACT_ROOT / "fixtures/valid").glob("*.yaml"))
    invalid = sorted((CONTRACT_ROOT / "fixtures/invalid").glob("*.yaml"))
    if not valid or not invalid:
        raise ContractError("fixtures: valid and invalid fixtures are both required")
    for fixture in valid:
        validate_request(load_yaml(fixture), schemas, products, paths, realms)
    for fixture in invalid:
        try:
            validate_request(load_yaml(fixture), schemas, products, paths, realms)
        except (ContractError, ValidationError):
            continue
        raise ContractError(f"invalid fixture unexpectedly passed: {fixture.relative_to(ROOT)}")


def validate_delivery_profile_fixtures(
    index: dict[str, Any], schemas: dict[str, Any]
) -> None:
    invalid = sorted((CONTRACT_ROOT / "fixtures/delivery-profiles/invalid").glob("*.yaml"))
    if not invalid:
        raise ContractError("fixtures: invalid delivery-profile fixtures are required")
    registry = {name: set(values) for name, values in index["spec"]["registries"].items()}
    schema_registry = Registry().with_resources(
        (schema_id, Resource.from_contents(schema))
        for schema_id, schema in schemas.items()
    )
    for fixture in invalid:
        profile = load_yaml(fixture)
        schema_version = profile.get("schemaVersion", "")
        schema_id = {
            "platform/delivery-profile/v1": "urn:darkfactory:platform-contract:delivery-profile:v1",
            "platform/delivery-profile/v2": "urn:darkfactory:platform-contract:delivery-profile:v2",
        }.get(schema_version)
        if not schema_id:
            continue
        validator = Draft202012Validator(
            schemas[schema_id], registry=schema_registry, format_checker=FORMAT_CHECKER
        )
        try:
            validator.validate(profile)
            validate_delivery_profile(profile, registry, fixture.relative_to(ROOT).as_posix())
        except (ContractError, ValidationError):
            continue
        raise ContractError(f"invalid fixture unexpectedly passed: {fixture.relative_to(ROOT)}")

    v2_profile = load_yaml(
        CONTRACT_ROOT
        / "delivery-profiles/argocd-preview-http-service/v2/profile.yaml"
    )
    mutations: list[tuple[str, dict[str, Any]]] = []

    worker_owned = copy.deepcopy(v2_profile)
    worker_owned["observerAccess"]["workerAuthorable"] = True
    mutations.append(("worker-authorable observer inventory", worker_owned))

    workload_role_binding = copy.deepcopy(v2_profile)
    workload_role_binding["resourceEnvelope"]["allowedKinds"].append(
        "rbac.authorization.k8s.io/v1/RoleBinding"
    )
    mutations.append(("workload RoleBinding", workload_role_binding))

    wildcard = copy.deepcopy(v2_profile)
    wildcard["observerAccess"]["inventoryClusterRole"]["rules"][0]["resources"] = ["*"]
    mutations.append(("wildcard observer role", wildcard))

    watch = copy.deepcopy(v2_profile)
    watch["observerAccess"]["inventoryClusterRole"]["rules"][0]["verbs"] = ["list", "watch"]
    mutations.append(("watch observer authority", watch))

    discovery = copy.deepcopy(v2_profile)
    discovery["observerAccess"]["inventoryClusterRole"]["rules"][0]["nonResourceURLs"] = ["/api"]
    mutations.append(("platform discovery authority", discovery))

    caller_subject = copy.deepcopy(v2_profile)
    caller_subject["observerAccess"]["realmRoleBinding"]["subject"]["nameFrom"] = (
        "request.inputs.observerServiceAccount"
    )
    mutations.append(("caller-controlled observer subject", caller_subject))

    changed_role_ref = copy.deepcopy(v2_profile)
    changed_role_ref["observerAccess"]["applicationRoleBinding"]["roleRef"]["kind"] = (
        "ClusterRole"
    )
    mutations.append(("changed observer roleRef", changed_role_ref))

    long_ttl = copy.deepcopy(v2_profile)
    long_ttl["observerAccess"]["credential"]["maxLifetime"] = "PT10M1S"
    mutations.append(("overlong observer credential", long_ttl))

    long_deadline = copy.deepcopy(v2_profile)
    long_deadline["observerAccess"]["credential"]["absoluteDeadline"] = "PT31S"
    mutations.append(("overlong observation deadline", long_deadline))

    no_cleanup = copy.deepcopy(v2_profile)
    del no_cleanup["observerAccess"]["cleanup"]
    mutations.append(("missing observer cleanup", no_cleanup))

    missing_inherited_authority = copy.deepcopy(v2_profile)
    del missing_inherited_authority["observerAccess"]["attestation"][
        "inheritedAuthorityEvidenceType"
    ]
    mutations.append(("missing inherited-authority evidence", missing_inherited_authority))

    incomplete_object_digests = copy.deepcopy(v2_profile)
    incomplete_object_digests["observerAccess"]["attestation"]["requiredObjectDigests"].pop()
    mutations.append(("incomplete authority object digests", incomplete_object_digests))

    stale_compensator = copy.deepcopy(v2_profile)
    stale_compensator["compensation"]["action"] = "delivery.revert-and-prune-preview/v1"
    stale_compensator["compensation"]["verifier"] = "realm.preview-pruned/v1"
    mutations.append(("observer access missing from compensator", stale_compensator))

    v2_validator = Draft202012Validator(
        schemas["urn:darkfactory:platform-contract:delivery-profile:v2"],
        registry=schema_registry,
        format_checker=FORMAT_CHECKER,
    )
    for name, profile in mutations:
        try:
            v2_validator.validate(profile)
            validate_delivery_profile(profile, registry, name)
        except (ContractError, ValidationError):
            continue
        raise ContractError(f"invalid v2 mutation unexpectedly passed: {name}")


def validate_runtime_schema_examples(schemas: dict[str, Any]) -> None:
    schema_registry = Registry().with_resources(
        (schema_id, Resource.from_contents(schema))
        for schema_id, schema in schemas.items()
    )
    def digest_for(value: str) -> str:
        return hashlib.sha256(value.encode("utf-8")).hexdigest()

    signature = "s" * 86
    work_order_id = "obscontract1"
    observer_name = f"obs-{work_order_id}"
    realm_name = f"preview-{work_order_id}"

    def object_evidence(
        api_version: str,
        kind: str,
        name: str,
        namespace: str | None = None,
    ) -> dict[str, Any]:
        value = {
            "apiVersion": api_version,
            "kind": kind,
            "name": name,
            "uid": f"uid-{kind.lower()}-{namespace or 'cluster'}-{name}",
            "resourceVersion": "101",
            "canonicalDigest": digest_for(f"{api_version}:{kind}:{namespace}:{name}"),
        }
        if namespace is not None:
            value["namespace"] = namespace
        return value

    negative_cases = (
        "appproject-get",
        "configmap-get",
        "configmap-list",
        "declared-resource-mutations",
        "foreign-application-get",
        "foreign-namespace-get",
        "foreign-realm-list",
        "foreign-tokenrequest-create",
        "impersonate-groups",
        "impersonate-serviceaccounts",
        "impersonate-userextras-scopes",
        "impersonate-users",
        "inventory-watch",
        "pod-exec-create",
        "pod-log-get",
        "pod-portforward-create",
        "secret-get",
        "secret-list",
        "sensitive-resource-watch",
        "service-proxy-get",
        "tokenrequest-create",
    )
    attestation = {
        "schemaVersion": "delivery/observer-access-attestation/v1",
        "workOrderId": work_order_id,
        "subject": (
            "system:serviceaccount:darkfactory-observers:"
            f"{observer_name}"
        ),
        "identityBinding": {
            "derivation": "workorder-derived-observer-access/v1",
            "canonicalDigest": digest_for("identity-binding"),
        },
        "semanticVerifier": "kubernetes.observer-rbac-attested/v1",
        "profileDigest": digest_for("observer-profile"),
        "cleanupPlanDigest": digest_for("cleanup-plan"),
        "controlInventoryDigest": digest_for("control-inventory"),
        "objects": {
            "applicationRole": object_evidence(
                "rbac.authorization.k8s.io/v1", "Role", observer_name, "argocd"
            ),
            "applicationRoleBinding": object_evidence(
                "rbac.authorization.k8s.io/v1", "RoleBinding", observer_name, "argocd"
            ),
            "inventoryClusterRole": object_evidence(
                "rbac.authorization.k8s.io/v1",
                "ClusterRole",
                "darkfactory-preview-delivery-list-v1",
            ),
            "namespaceClusterRole": object_evidence(
                "rbac.authorization.k8s.io/v1", "ClusterRole", observer_name
            ),
            "namespaceClusterRoleBinding": object_evidence(
                "rbac.authorization.k8s.io/v1", "ClusterRoleBinding", observer_name
            ),
            "realmRoleBinding": object_evidence(
                "rbac.authorization.k8s.io/v1", "RoleBinding", observer_name, realm_name
            ),
            "serviceAccount": object_evidence(
                "v1", "ServiceAccount", observer_name, "darkfactory-observers"
            ),
        },
        "negativeAuthorization": {
            case: {
                "decision": "denied",
                "requestDigest": digest_for(f"request:{case}"),
                "responseDigest": digest_for(f"response:{case}"),
            }
            for case in negative_cases
        },
        "negativeAuthorizationMatrixDigest": digest_for("negative-matrix"),
        "inheritedAuthority": {
            "reported": True,
            "complete": True,
            "evaluationMode": "exact-profile-and-baseline-delta",
            "baselineProfileDigest": digest_for("authenticated-authority-baseline-profile"),
            "baselineRulesDigest": digest_for("authenticated-authority-baseline-rules"),
            "profileGrantDigest": digest_for("observer-profile-grants"),
            "effectiveAuthorityDigest": digest_for("effective-observer-authority"),
            "resourceRules": [],
            "nonResourceRules": [],
            "canonicalDigest": digest_for("inherited-authority"),
        },
        "attestor": {
            "profileDigest": digest_for("attestor-profile"),
            "subject": "system:serviceaccount:darkfactory-attestors:rbac-attestor",
            "independentFromObserver": True,
            "signingKeyId": "kms:preview-attestor-v1",
        },
        "signature": {
            "algorithm": "ECDSA_SHA_256",
            "keyId": "kms:preview-attestor-v1",
            "value": signature,
        },
        "observedAt": "2026-07-14T00:00:00Z",
        "canonicalization": "rfc8785-json-canonicalization/v1",
        "digestPayloadExcludes": ["evidenceSha256", "signature.value"],
        "evidenceSha256": digest_for("authority-evidence"),
    }

    scope = {
        "schemaVersion": "delivery/observation-scope/v1",
        "workOrderId": work_order_id,
        "subject": attestation["subject"],
        "identityDerivation": "workorder-derived-observer-scope/v1",
        "identityBindingDigest": attestation["identityBinding"]["canonicalDigest"],
        "adapterBindingDigest": digest_for("adapter-binding"),
        "semanticVerifier": "kubernetes.observation-scope-bound/v1",
        "audience": "https://kubernetes.default.svc.cluster.local",
        "apiServer": "https://127.0.0.1:6443",
        "caSha256": digest_for("cluster-ca"),
        "application": {"namespace": "argocd", "name": realm_name, "uid": "uid-app"},
        "namespace": {"name": realm_name, "uid": "uid-namespace"},
        "operations": ["application.get", "namespace.get", "realm.list"],
        "kindIds": [
            "apps/v1/Deployment",
            "apps/v1/ReplicaSet",
            "networking.k8s.io/v1/Ingress",
            "networking.k8s.io/v1/NetworkPolicy",
            "rbac.authorization.k8s.io/v1/Role",
            "rbac.authorization.k8s.io/v1/RoleBinding",
            "v1/PersistentVolumeClaim",
            "v1/Pod",
            "v1/ResourceQuota",
            "v1/Service",
            "v1/ServiceAccount",
        ],
        "issuedAt": "2026-07-14T00:00:00Z",
        "expiresAt": "2026-07-14T00:10:00Z",
        "deadline": "2026-07-14T00:00:30Z",
        "maxObjects": 100,
        "maxResponseBytes": 1048576,
        "issuer": {
            "profileDigest": digest_for("scope-issuer-profile"),
            "subject": "system:serviceaccount:darkfactory-attestors:scope-issuer",
            "signingKeyId": "kms:preview-scope-v1",
            "algorithm": "ECDSA_SHA_256",
            "signature": signature,
        },
        "canonicalization": "rfc8785-json-canonicalization/v1",
        "digestPayloadExcludes": ["issuer.signature", "scopeSha256"],
        "scopeSha256": digest_for("observation-scope"),
    }

    snapshot_kinds = {
        "apps-v1-deployments": "apps/v1/Deployment",
        "apps-v1-replicasets": "apps/v1/ReplicaSet",
        "networking-v1-ingresses": "networking.k8s.io/v1/Ingress",
        "networking-v1-networkpolicies": "networking.k8s.io/v1/NetworkPolicy",
        "rbac-v1-rolebindings": "rbac.authorization.k8s.io/v1/RoleBinding",
        "rbac-v1-roles": "rbac.authorization.k8s.io/v1/Role",
        "v1-persistentvolumeclaims": "v1/PersistentVolumeClaim",
        "v1-pods": "v1/Pod",
        "v1-resourcequotas": "v1/ResourceQuota",
        "v1-serviceaccounts": "v1/ServiceAccount",
        "v1-services": "v1/Service",
    }
    snapshots = {
        key: {
            "schemaVersion": "delivery/namespaced-resource-snapshot/v1",
            "kindId": kind_id,
            "resourceVersion": "202",
            "items": [],
            "canonicalDigest": digest_for(f"snapshot:{kind_id}"),
        }
        for key, kind_id in snapshot_kinds.items()
    }
    observation = {
        "schemaVersion": "delivery/observation-evidence/v1",
        "workOrderId": work_order_id,
        "identityBindingDigest": attestation["identityBinding"]["canonicalDigest"],
        "adapterBindingDigest": scope["adapterBindingDigest"],
        "scopeDigest": scope["scopeSha256"],
        "semanticVerifier": "realm.preview-delivery-observed/v1",
        "applicationUid": "uid-app",
        "applicationGeneration": 1,
        "namespaceUid": "uid-namespace",
        "mergeCommitSha": "b" * 40,
        "imageDigest": f"sha256:{digest_for('image')}",
        "renderedInventoryDigest": digest_for("rendered-inventory"),
        "repositoryAuthorizationDigest": digest_for("repository-authorization"),
        "controlInventoryDigest": attestation["controlInventoryDigest"],
        "controlObjectDigests": {
            name: value["canonicalDigest"]
            for name, value in attestation["objects"].items()
        },
        "admissionRbacDigest": attestation["evidenceSha256"],
        "inheritedAuthorityDigest": attestation["inheritedAuthority"]["canonicalDigest"],
        "transportRecordingDigest": digest_for("transport-recording"),
        "totalObjectCount": 0,
        "finalCollectionSnapshots": snapshots,
        "canonicalization": "rfc8785-json-canonicalization/v1",
        "digestPayloadExcludes": ["evidenceSha256", "verifier.signature"],
        "evidenceSha256": digest_for("delivery-observation"),
        "observedAt": "2026-07-14T00:00:00Z",
        "expiresAt": "2026-07-15T00:00:00Z",
        "verifier": {
            "profileDigest": digest_for("delivery-verifier-profile"),
            "subject": "system:serviceaccount:darkfactory-attestors:delivery-verifier",
            "signingKeyId": "kms:preview-delivery-v1",
            "algorithm": "ECDSA_SHA_256",
            "signature": signature,
        },
    }
    cleanup_object_names = (
        "applicationRole",
        "applicationRoleBinding",
        "namespaceClusterRole",
        "namespaceClusterRoleBinding",
        "realmRoleBinding",
        "serviceAccount",
    )
    cleanup = {
        "schemaVersion": "delivery/observer-access-cleanup-evidence/v1",
        "workOrderId": work_order_id,
        "identityBindingDigest": attestation["identityBinding"]["canonicalDigest"],
        "cleanupPlanDigest": attestation["cleanupPlanDigest"],
        "safeToReclaimDecision": {
            "workOrderId": work_order_id,
            "policy": "delivery.observer-access-safe-to-reclaim/v1",
            "decision": "allowed",
            "workOrderState": "terminal",
            "workOrderStateDigest": digest_for("terminal-work-order-state"),
            "semanticVerifier": "delivery.observer-access-safe-to-reclaim/v1",
            "issuer": {
                "profileDigest": digest_for("safe-to-reclaim-issuer-profile"),
                "subject": "system:serviceaccount:darkfactory-attestors:reclaim-issuer",
                "independentFromCleanupExecutor": True,
                "signingKeyId": "kms:preview-reclaim-v1",
                "algorithm": "ECDSA_SHA_256",
                "signature": signature,
            },
            "decidedAt": "2026-07-14T00:00:45Z",
            "canonicalization": "rfc8785-json-canonicalization/v1",
            "digestPayloadExcludes": ["issuer.signature", "decisionDigest"],
            "decisionDigest": digest_for("safe-to-reclaim"),
        },
        "leaseRevoked": True,
        "workOrderObjects": {
            name: {
                "expectedUid": attestation["objects"][name]["uid"],
                "expectedResourceVersion": attestation["objects"][name][
                    "resourceVersion"
                ],
                "expectedCanonicalDigest": attestation["objects"][name]["canonicalDigest"],
                "deleteResult": "deleted",
                "status": "absent",
            }
            for name in cleanup_object_names
        },
        "sharedInventoryClusterRole": {
            "name": "darkfactory-preview-delivery-list-v1",
            "status": "preserved",
            "canonicalDigest": attestation["objects"]["inventoryClusterRole"][
                "canonicalDigest"
            ],
        },
        "ambiguousEffects": [],
        "verifier": {
            "profileDigest": digest_for("cleanup-verifier-profile"),
            "subject": "system:serviceaccount:darkfactory-attestors:cleanup-verifier",
            "signingKeyId": "kms:preview-cleanup-v1",
            "algorithm": "ECDSA_SHA_256",
            "signature": signature,
        },
        "verifiedAt": "2026-07-14T00:01:00Z",
        "canonicalization": "rfc8785-json-canonicalization/v1",
        "digestPayloadExcludes": ["evidenceSha256", "verifier.signature"],
        "evidenceSha256": digest_for("cleanup-evidence"),
    }
    trusted_profiles = {
        "attestor": (digest_for("attestor-profile"), "kms:preview-attestor-v1"),
        "scopeIssuer": (digest_for("scope-issuer-profile"), "kms:preview-scope-v1"),
        "deliveryVerifier": (
            digest_for("delivery-verifier-profile"),
            "kms:preview-delivery-v1",
        ),
        "cleanupVerifier": (
            digest_for("cleanup-verifier-profile"),
            "kms:preview-cleanup-v1",
        ),
        "reclaimIssuer": (
            digest_for("safe-to-reclaim-issuer-profile"),
            "kms:preview-reclaim-v1",
        ),
        "authorityBaseline": (
            digest_for("authenticated-authority-baseline-profile"),
            digest_for("authenticated-authority-baseline-rules"),
        ),
    }

    def validate_runtime_semantics(
        authority: dict[str, Any],
        observation_scope: dict[str, Any],
        delivery_evidence: dict[str, Any],
        cleanup_evidence: dict[str, Any],
    ) -> None:
        expected_work_order = authority["workOrderId"]
        expected_observer = f"obs-{expected_work_order}"
        expected_realm = f"preview-{expected_work_order}"
        expected_subject = (
            "system:serviceaccount:darkfactory-observers:"
            f"{expected_observer}"
        )
        work_order_values = {
            observation_scope["workOrderId"],
            delivery_evidence["workOrderId"],
            cleanup_evidence["workOrderId"],
        }
        if work_order_values != {expected_work_order}:
            raise ContractError("runtime evidence crosses WorkOrder identities")
        if (
            authority["subject"] != expected_subject
            or observation_scope["subject"] != expected_subject
        ):
            raise ContractError("runtime evidence subject is not WorkOrder-derived")
        if authority["attestor"]["subject"] == expected_subject:
            raise ContractError("authority attestor is the observer principal")

        presented_profiles = {
            "attestor": (
                authority["attestor"]["profileDigest"],
                authority["attestor"]["signingKeyId"],
            ),
            "scopeIssuer": (
                observation_scope["issuer"]["profileDigest"],
                observation_scope["issuer"]["signingKeyId"],
            ),
            "deliveryVerifier": (
                delivery_evidence["verifier"]["profileDigest"],
                delivery_evidence["verifier"]["signingKeyId"],
            ),
            "cleanupVerifier": (
                cleanup_evidence["verifier"]["profileDigest"],
                cleanup_evidence["verifier"]["signingKeyId"],
            ),
            "reclaimIssuer": (
                cleanup_evidence["safeToReclaimDecision"]["issuer"]["profileDigest"],
                cleanup_evidence["safeToReclaimDecision"]["issuer"]["signingKeyId"],
            ),
            "authorityBaseline": (
                authority["inheritedAuthority"]["baselineProfileDigest"],
                authority["inheritedAuthority"]["baselineRulesDigest"],
            ),
        }
        if presented_profiles != trusted_profiles:
            raise ContractError("runtime evidence signer is not bound to its adapter trust anchor")
        inherited = authority["inheritedAuthority"]
        if (
            inherited["resourceRules"] != []
            or inherited["nonResourceRules"] != []
            or inherited["evaluationMode"] != "exact-profile-and-baseline-delta"
        ):
            raise ContractError("inherited authority has a residual profile/baseline delta")

        expected_control_names = {
            "applicationRole": expected_observer,
            "applicationRoleBinding": expected_observer,
            "inventoryClusterRole": "darkfactory-preview-delivery-list-v1",
            "namespaceClusterRole": expected_observer,
            "namespaceClusterRoleBinding": expected_observer,
            "realmRoleBinding": expected_observer,
            "serviceAccount": expected_observer,
        }
        for name, expected_name in expected_control_names.items():
            if authority["objects"][name]["name"] != expected_name:
                raise ContractError(f"runtime control object {name} is not WorkOrder-derived")
        if authority["objects"]["realmRoleBinding"]["namespace"] != expected_realm:
            raise ContractError("Realm RoleBinding is outside the WorkOrder Realm")
        if observation_scope["application"]["name"] != expected_realm:
            raise ContractError("Application identity is not WorkOrder-derived")
        if observation_scope["namespace"]["name"] != expected_realm:
            raise ContractError("Namespace identity is not WorkOrder-derived")

        identity_digest = authority["identityBinding"]["canonicalDigest"]
        if {
            observation_scope["identityBindingDigest"],
            delivery_evidence["identityBindingDigest"],
            cleanup_evidence["identityBindingDigest"],
        } != {identity_digest}:
            raise ContractError("runtime identity binding digests disagree")
        if (
            delivery_evidence["adapterBindingDigest"]
            != observation_scope["adapterBindingDigest"]
        ):
            raise ContractError("runtime adapter binding digests disagree")
        if delivery_evidence["scopeDigest"] != observation_scope["scopeSha256"]:
            raise ContractError("delivery evidence is not bound to its scope")

        issued_at = datetime.fromisoformat(observation_scope["issuedAt"].replace("Z", "+00:00"))
        deadline = datetime.fromisoformat(observation_scope["deadline"].replace("Z", "+00:00"))
        expires_at = datetime.fromisoformat(observation_scope["expiresAt"].replace("Z", "+00:00"))
        authority_time = datetime.fromisoformat(authority["observedAt"].replace("Z", "+00:00"))
        observation_time = datetime.fromisoformat(
            delivery_evidence["observedAt"].replace("Z", "+00:00")
        )
        evidence_expiry = datetime.fromisoformat(
            delivery_evidence["expiresAt"].replace("Z", "+00:00")
        )
        if not issued_at - timedelta(seconds=30) <= authority_time <= issued_at:
            raise ContractError("RBAC attestation is stale or follows credential issuance")
        if not issued_at < deadline <= issued_at + timedelta(seconds=30):
            raise ContractError("observation deadline is outside the signed scope")
        if not deadline < expires_at <= issued_at + timedelta(minutes=10):
            raise ContractError("observer credential lifetime is outside the signed scope")
        if not issued_at <= observation_time <= deadline:
            raise ContractError("delivery observation is outside the signed deadline")
        if not observation_time < evidence_expiry <= observation_time + timedelta(hours=24):
            raise ContractError("delivery evidence freshness exceeds the Condition of Done")

        total_objects = 0
        for snapshot in delivery_evidence["finalCollectionSnapshots"].values():
            item_names = [(item["namespace"], item["name"]) for item in snapshot["items"]]
            item_uids = [item["uid"] for item in snapshot["items"]]
            if (
                len(item_names) != len(set(item_names))
                or len(item_uids) != len(set(item_uids))
            ):
                raise ContractError("snapshot contains duplicate name or UID")
            if any(item["namespace"] != expected_realm for item in snapshot["items"]):
                raise ContractError("snapshot contains a foreign Realm item")
            total_objects += len(snapshot["items"])
        if delivery_evidence["totalObjectCount"] != total_objects or total_objects > 100:
            raise ContractError("delivery evidence object count is false or unbounded")

        if (
            delivery_evidence["applicationUid"]
            != observation_scope["application"]["uid"]
        ):
            raise ContractError("Application UID differs between scope and evidence")
        if delivery_evidence["namespaceUid"] != observation_scope["namespace"]["uid"]:
            raise ContractError("Namespace UID differs between scope and evidence")
        if (
            delivery_evidence["controlInventoryDigest"]
            != authority["controlInventoryDigest"]
        ):
            raise ContractError("control inventory digest differs from authority evidence")
        if delivery_evidence["admissionRbacDigest"] != authority["evidenceSha256"]:
            raise ContractError("delivery evidence is not bound to its RBAC attestation")
        if (
            delivery_evidence["inheritedAuthorityDigest"]
            != authority["inheritedAuthority"]["canonicalDigest"]
        ):
            raise ContractError("delivery evidence is not bound to inherited authority")
        for name, object_evidence_value in authority["objects"].items():
            if (
                delivery_evidence["controlObjectDigests"][name]
                != object_evidence_value["canonicalDigest"]
            ):
                raise ContractError(f"control object digest differs for {name}")

        independent_digests = [
            delivery_evidence["renderedInventoryDigest"],
            delivery_evidence["repositoryAuthorizationDigest"],
            delivery_evidence["controlInventoryDigest"],
            delivery_evidence["admissionRbacDigest"],
            delivery_evidence["inheritedAuthorityDigest"],
            delivery_evidence["transportRecordingDigest"],
            *(
                snapshot["canonicalDigest"]
                for snapshot in delivery_evidence["finalCollectionSnapshots"].values()
            ),
        ]
        if len(independent_digests) != len(set(independent_digests)):
            raise ContractError("authority and state evidence digests are reused")

        if (
            cleanup_evidence["sharedInventoryClusterRole"]["canonicalDigest"]
            != authority["objects"]["inventoryClusterRole"]["canonicalDigest"]
        ):
            raise ContractError("cleanup altered the shared inventory ClusterRole")
        if cleanup_evidence["cleanupPlanDigest"] != authority["cleanupPlanDigest"]:
            raise ContractError("cleanup is not bound to the registered cleanup plan")
        reclaim = cleanup_evidence["safeToReclaimDecision"]
        if (
            reclaim["workOrderId"] != expected_work_order
            or reclaim["decision"] != "allowed"
            or reclaim["workOrderState"] not in {"absent", "terminal"}
        ):
            raise ContractError("cleanup lacks a positive WorkOrder-bound reclaim decision")
        if (
            reclaim["issuer"]["subject"] == cleanup_evidence["verifier"]["subject"]
            or reclaim["issuer"]["signingKeyId"]
            == cleanup_evidence["verifier"]["signingKeyId"]
        ):
            raise ContractError("reclaim decision is not independent from cleanup verification")
        if reclaim["decisionDigest"] == reclaim["workOrderStateDigest"]:
            raise ContractError("reclaim decision reuses its WorkOrder state digest")
        reclaim_time = datetime.fromisoformat(reclaim["decidedAt"].replace("Z", "+00:00"))
        cleanup_time = datetime.fromisoformat(
            cleanup_evidence["verifiedAt"].replace("Z", "+00:00")
        )
        if reclaim_time > cleanup_time:
            raise ContractError("cleanup precedes its safe-to-reclaim decision")
        if cleanup_time < observation_time:
            raise ContractError("cleanup verification predates delivery observation")
        for name in cleanup_object_names:
            expected_object = authority["objects"][name]
            result = cleanup_evidence["workOrderObjects"][name]
            if result["expectedUid"] != expected_object["uid"]:
                raise ContractError(f"cleanup UID differs for {name}")
            if result["expectedResourceVersion"] != expected_object["resourceVersion"]:
                raise ContractError(f"cleanup resourceVersion differs for {name}")
            if (
                result["expectedCanonicalDigest"]
                != expected_object["canonicalDigest"]
            ):
                raise ContractError(f"cleanup digest differs for {name}")

        if (
            authority["signature"]["keyId"]
            != authority["attestor"]["signingKeyId"]
        ):
            raise ContractError("authority signature key does not match its attestor")

    examples = {
        "urn:darkfactory:platform-contract:observer-access-attestation:v1": attestation,
        "urn:darkfactory:platform-contract:observer-access-cleanup-evidence:v1": cleanup,
        "urn:darkfactory:platform-contract:observation-scope:v1": scope,
        "urn:darkfactory:platform-contract:delivery-observation-evidence:v1": observation,
    }
    for schema_id, example in examples.items():
        Draft202012Validator(
            schemas[schema_id], registry=schema_registry, format_checker=FORMAT_CHECKER
        ).validate(example)
    validate_runtime_semantics(attestation, scope, observation, cleanup)

    invalid_examples = []
    scope_with_token = copy.deepcopy(scope)
    scope_with_token["token"] = "must-never-enter-evidence"
    invalid_examples.append(
        (
            "observation scope token",
            "urn:darkfactory:platform-contract:observation-scope:v1",
            scope_with_token,
        )
    )

    allowed_secret = copy.deepcopy(attestation)
    allowed_secret["negativeAuthorization"]["secret-list"]["decision"] = "allowed"
    invalid_examples.append(
        (
            "allowed Secret",
            "urn:darkfactory:platform-contract:observer-access-attestation:v1",
            allowed_secret,
        )
    )

    wrong_snapshot = copy.deepcopy(observation)
    wrong_snapshot["finalCollectionSnapshots"]["v1-pods"]["kindId"] = "v1/Service"
    invalid_examples.append(
        (
            "wrong keyed snapshot kind",
            "urn:darkfactory:platform-contract:delivery-observation-evidence:v1",
            wrong_snapshot,
        )
    )

    oversized_realm = copy.deepcopy(observation)
    oversized_realm["totalObjectCount"] = 101
    invalid_examples.append(
        (
            "oversized Realm",
            "urn:darkfactory:platform-contract:delivery-observation-evidence:v1",
            oversized_realm,
        )
    )

    invalid_timestamp = copy.deepcopy(scope)
    invalid_timestamp["issuedAt"] = "not-a-timestamp"
    invalid_examples.append(
        (
            "invalid signed timestamp",
            "urn:darkfactory:platform-contract:observation-scope:v1",
            invalid_timestamp,
        )
    )

    for name, schema_id, example in invalid_examples:
        validator = Draft202012Validator(
            schemas[schema_id], registry=schema_registry, format_checker=FORMAT_CHECKER
        )
        try:
            validator.validate(example)
        except ValidationError:
            continue
        raise ContractError(f"invalid runtime schema example unexpectedly passed: {name}")

    semantic_mutations = []
    cross_work_order_scope = copy.deepcopy(scope)
    cross_work_order_scope["subject"] = (
        "system:serviceaccount:darkfactory-observers:obs-otherwork1"
    )
    semantic_mutations.append(
        ("cross-WorkOrder scope", attestation, cross_work_order_scope, observation, cleanup)
    )

    overlong_scope = copy.deepcopy(scope)
    overlong_scope["deadline"] = "2026-07-14T00:00:31Z"
    semantic_mutations.append(
        ("overlong absolute deadline", attestation, overlong_scope, observation, cleanup)
    )

    false_total = copy.deepcopy(observation)
    false_total["totalObjectCount"] = 1
    semantic_mutations.append(
        ("false total object count", attestation, scope, false_total, cleanup)
    )

    reused_authority = copy.deepcopy(observation)
    reused_authority["transportRecordingDigest"] = reused_authority[
        "repositoryAuthorizationDigest"
    ]
    semantic_mutations.append(
        ("reused independent evidence", attestation, scope, reused_authority, cleanup)
    )

    altered_shared_role = copy.deepcopy(cleanup)
    altered_shared_role["sharedInventoryClusterRole"]["canonicalDigest"] = digest_for(
        "altered-shared-role"
    )
    semantic_mutations.append(
        ("altered shared role", attestation, scope, observation, altered_shared_role)
    )

    foreign_rbac_attestation = copy.deepcopy(observation)
    foreign_rbac_attestation["admissionRbacDigest"] = digest_for("foreign-rbac-attestation")
    semantic_mutations.append(
        (
            "foreign RBAC attestation",
            attestation,
            scope,
            foreign_rbac_attestation,
            cleanup,
        )
    )

    foreign_inherited_authority = copy.deepcopy(observation)
    foreign_inherited_authority["inheritedAuthorityDigest"] = digest_for(
        "foreign-inherited-authority"
    )
    semantic_mutations.append(
        (
            "foreign inherited authority",
            attestation,
            scope,
            foreign_inherited_authority,
            cleanup,
        )
    )

    foreign_reclaim_decision = copy.deepcopy(cleanup)
    foreign_reclaim_decision["safeToReclaimDecision"]["workOrderId"] = "otherwork1"
    semantic_mutations.append(
        (
            "foreign safe-to-reclaim decision",
            attestation,
            scope,
            observation,
            foreign_reclaim_decision,
        )
    )

    foreign_cleanup_plan = copy.deepcopy(cleanup)
    foreign_cleanup_plan["cleanupPlanDigest"] = digest_for("foreign-cleanup-plan")
    semantic_mutations.append(
        (
            "foreign cleanup plan",
            attestation,
            scope,
            observation,
            foreign_cleanup_plan,
        )
    )

    stale_attestation = copy.deepcopy(attestation)
    stale_attestation["observedAt"] = "2026-07-13T23:59:29Z"
    semantic_mutations.append(
        ("stale RBAC attestation", stale_attestation, scope, observation, cleanup)
    )

    late_observation = copy.deepcopy(observation)
    late_observation["observedAt"] = "2026-07-14T00:00:31Z"
    semantic_mutations.append(
        ("late delivery observation", attestation, scope, late_observation, cleanup)
    )

    reused_reclaim_digest = copy.deepcopy(cleanup)
    reused_reclaim_digest["safeToReclaimDecision"]["decisionDigest"] = (
        reused_reclaim_digest["safeToReclaimDecision"]["workOrderStateDigest"]
    )
    semantic_mutations.append(
        (
            "reused reclaim decision digest",
            attestation,
            scope,
            observation,
            reused_reclaim_digest,
        )
    )

    attacker_delivery_verifier = copy.deepcopy(observation)
    attacker_delivery_verifier["verifier"]["profileDigest"] = digest_for(
        "attacker-delivery-profile"
    )
    attacker_delivery_verifier["verifier"]["signingKeyId"] = "kms:attacker-delivery"
    semantic_mutations.append(
        (
            "attacker delivery verifier",
            attestation,
            scope,
            attacker_delivery_verifier,
            cleanup,
        )
    )

    attacker_cleanup_verifier = copy.deepcopy(cleanup)
    attacker_cleanup_verifier["verifier"]["profileDigest"] = digest_for(
        "attacker-cleanup-profile"
    )
    attacker_cleanup_verifier["verifier"]["signingKeyId"] = "kms:attacker-cleanup"
    semantic_mutations.append(
        (
            "attacker cleanup verifier",
            attestation,
            scope,
            observation,
            attacker_cleanup_verifier,
        )
    )

    attacker_reclaim_issuer = copy.deepcopy(cleanup)
    attacker_reclaim_issuer["safeToReclaimDecision"]["issuer"]["profileDigest"] = (
        digest_for("attacker-reclaim-profile")
    )
    attacker_reclaim_issuer["safeToReclaimDecision"]["issuer"]["signingKeyId"] = (
        "kms:attacker-reclaim"
    )
    semantic_mutations.append(
        (
            "attacker reclaim issuer",
            attestation,
            scope,
            observation,
            attacker_reclaim_issuer,
        )
    )

    attacker_authority_baseline = copy.deepcopy(attestation)
    attacker_authority_baseline["inheritedAuthority"]["baselineProfileDigest"] = (
        digest_for("attacker-authority-baseline-profile")
    )
    semantic_mutations.append(
        (
            "attacker authority baseline",
            attacker_authority_baseline,
            scope,
            observation,
            cleanup,
        )
    )

    replacement_object_cleanup = copy.deepcopy(cleanup)
    replacement_object_cleanup["workOrderObjects"]["serviceAccount"][
        "expectedResourceVersion"
    ] = "replacement-resource-version"
    semantic_mutations.append(
        (
            "replacement object cleanup",
            attestation,
            scope,
            observation,
            replacement_object_cleanup,
        )
    )

    for name, authority, observation_scope, delivery_evidence, cleanup_evidence in semantic_mutations:
        try:
            validate_runtime_semantics(
                authority, observation_scope, delivery_evidence, cleanup_evidence
            )
        except ContractError:
            continue
        raise ContractError(f"invalid runtime semantic mutation unexpectedly passed: {name}")


def main() -> int:
    try:
        index = load_yaml(INDEX_PATH)
        artifacts = validate_index(index)
        validate_digests(index, artifacts)
        schemas, documents = load_and_validate_artifacts(artifacts)
        products, paths, realms, delivery_profiles = validate_semantics(index, schemas, documents)
        validate_fixtures(schemas, products, paths, realms)
        validate_delivery_profile_fixtures(index, schemas)
        validate_runtime_schema_examples(schemas)
    except Exception as error:
        print(f"platform-contract validation failed: {error}", file=sys.stderr)
        return 1
    print(
        "platform-contract validation passed: "
        f"{len(artifacts)} indexed artifacts, {len(products)} product, "
        f"{len(paths)} path, {len(realms)} Realm, "
        f"{len(delivery_profiles)} delivery profile"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
