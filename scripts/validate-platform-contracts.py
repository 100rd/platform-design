#!/usr/bin/env python3
"""Validate the indexed darkfactory platform-contract bundle."""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator, ValidationError
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_ROOT = ROOT / "platform-contracts"
INDEX_PATH = CONTRACT_ROOT / "index.yaml"


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
        validator = Draft202012Validator(schemas[schema_id], registry=registry)
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
    if set(envelope["requiredAssertions"]) != required_assertions:
        raise ContractError(f"{context}: preview containment assertions are incomplete")
    if envelope["requiredAssertions"] != sorted(envelope["requiredAssertions"]):
        raise ContractError(f"{context}: requiredAssertions must be sorted")
    expected_compensation_scope = {
        "repositoryFrom": "source.repositoryFrom",
        "gitopsPathFrom": "source.gitopsPathTemplate",
        "applicationNameFrom": "application.nameTemplate",
        "destinationNamespaceFrom": "destination.namespaceTemplate",
        "inventoryDigestFrom": "source.desiredInventoryFrom",
        "ownershipLabelFrom": "resourceEnvelope.ownershipLabel",
        "ownershipValueFrom": "resourceEnvelope.ownershipValueFrom",
    }
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
        for realm_id in path["supportedRealms"]:
            if realm_id not in realms:
                raise ContractError(f"{path_id}: unknown Realm {realm_id}")
            realm = realms[realm_id]
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
    Draft202012Validator(schemas["urn:darkfactory:platform-contract:product-request:v1"]).validate(request)
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
    Draft202012Validator(schemas[path["inputSchema"]]).validate(request["inputs"])


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
    schema = schemas["urn:darkfactory:platform-contract:delivery-profile:v1"]
    registry = {name: set(values) for name, values in index["spec"]["registries"].items()}
    validator = Draft202012Validator(schema)
    for fixture in invalid:
        profile = load_yaml(fixture)
        try:
            validator.validate(profile)
            validate_delivery_profile(profile, registry, fixture.relative_to(ROOT).as_posix())
        except (ContractError, ValidationError):
            continue
        raise ContractError(f"invalid fixture unexpectedly passed: {fixture.relative_to(ROOT)}")


def main() -> int:
    try:
        index = load_yaml(INDEX_PATH)
        artifacts = validate_index(index)
        validate_digests(index, artifacts)
        schemas, documents = load_and_validate_artifacts(artifacts)
        products, paths, realms, delivery_profiles = validate_semantics(index, schemas, documents)
        validate_fixtures(schemas, products, paths, realms)
        validate_delivery_profile_fixtures(index, schemas)
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
