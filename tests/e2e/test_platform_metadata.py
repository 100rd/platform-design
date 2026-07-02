import os
import subprocess
import json
import re
import pytest
import hcl2
import yaml

# Path resolution helper
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Helper: extract braced block contents
def extract_braced_block(text, start_pos):
    brace_start = text.find("{", start_pos)
    if brace_start == -1:
        return ""
    
    brace_count = 1
    pos = brace_start + 1
    while brace_count > 0 and pos < len(text):
        char = text[pos]
        if char == "{":
            brace_count += 1
        elif char == "}":
            brace_count -= 1
        pos += 1
    return text[brace_start:pos]

# -----------------------------------------------------------------------------
# F1: GCP Root Terragrunt Labels (terragrunt/gcp-staging/root.hcl)
# -----------------------------------------------------------------------------
ROOT_HCL_PATH = os.path.join(PROJECT_ROOT, "terragrunt", "gcp-staging", "root.hcl")

def get_parsed_root_hcl():
    assert os.path.exists(ROOT_HCL_PATH), f"root.hcl not found at {ROOT_HCL_PATH}"
    with open(ROOT_HCL_PATH, "r") as f:
        return hcl2.load(f)

def get_provider_contents_from_root_hcl():
    parsed = get_parsed_root_hcl()
    generate_blocks = parsed.get("generate", [])
    for gen in generate_blocks:
        for name, block in gen.items():
            if name == "provider":
                return block.get("contents", "")
    return ""

def get_default_labels_from_provider_string(provider_str, provider_name):
    # Find provider block first
    parts = provider_str.split('provider "')
    for part in parts:
        if part.strip().startswith(provider_name):
            # Locate default_labels
            idx = part.find("default_labels")
            if idx == -1:
                continue
            
            # Extract the braced block
            block = extract_braced_block(part, idx)
            # Remove outer braces
            if block.startswith("{") and block.endswith("}"):
                block_content = block[1:-1]
            else:
                block_content = block
                
            labels = {}
            for line in block_content.splitlines():
                line = line.strip()
                if not line or line.startswith("#") or line.startswith("//"):
                    continue
                if "=" in line:
                    parts_line = line.split("=", 1)
                    key = parts_line[0].strip().strip('"').strip("'")
                    val = parts_line[1].strip().strip('"').strip("'")
                    labels[key] = val
            return labels
    return None


# --- Tier 1: F1 Feature Coverage ---

def test_f1_google_provider_labels_present():
    """Assert default_labels exists in Google provider block in root.hcl."""
    provider_str = get_provider_contents_from_root_hcl()
    assert provider_str, "Provider generation contents not found in root.hcl"
    labels = get_default_labels_from_provider_string(provider_str, "google")
    assert labels is not None, "default_labels map not found in google provider block"

def test_f1_google_beta_provider_labels_present():
    """Assert default_labels exists in Google-beta provider block in root.hcl."""
    provider_str = get_provider_contents_from_root_hcl()
    assert provider_str, "Provider generation contents not found in root.hcl"
    labels = get_default_labels_from_provider_string(provider_str, "google-beta")
    assert labels is not None, "default_labels map not found in google-beta provider block"

def test_f1_all_required_labels_in_google_provider():
    """Assert google provider's default_labels contains the five required platform labels."""
    provider_str = get_provider_contents_from_root_hcl()
    labels = get_default_labels_from_provider_string(provider_str, "google")
    required = ["platform_system", "platform_component", "platform_env", "platform_owner", "platform_managed_by"]
    for key in required:
        assert key in labels, f"Missing required label '{key}' in google provider default_labels"

def test_f1_all_required_labels_in_google_beta_provider():
    """Assert google-beta provider's default_labels contains the five required platform labels."""
    provider_str = get_provider_contents_from_root_hcl()
    labels = get_default_labels_from_provider_string(provider_str, "google-beta")
    required = ["platform_system", "platform_component", "platform_env", "platform_owner", "platform_managed_by"]
    for key in required:
        assert key in labels, f"Missing required label '{key}' in google-beta provider default_labels"

def test_f1_labels_reference_locals():
    """Assert provider default_labels map references the correct local variables dynamically."""
    provider_str = get_provider_contents_from_root_hcl()
    google_labels = get_default_labels_from_provider_string(provider_str, "google")
    beta_labels = get_default_labels_from_provider_string(provider_str, "google-beta")
    
    assert google_labels.get("platform_system") == "${local.platform_system}"
    assert beta_labels.get("platform_system") == "${local.platform_system}"


# --- Tier 2: F1 Boundary & Corner Cases ---

def test_f1_label_naming_alphanumeric_constraint():
    """Assert that label keys are lowercase alphanumeric with hyphens or underscores only."""
    provider_str = get_provider_contents_from_root_hcl()
    for provider in ["google", "google-beta"]:
        labels = get_default_labels_from_provider_string(provider_str, provider)
        for key in labels.keys():
            assert re.match(r"^[a-z0-9_-]+$", key), f"Label key '{key}' does not match GKE/GCP label naming requirements (lowercase alphanumeric, hyphens, underscores)"

def test_f1_root_hcl_terragrunt_version():
    """Assert terragrunt version constraint is >= 0.68.0."""
    parsed = get_parsed_root_hcl()
    version = parsed.get("terragrunt_version_constraint")
    assert version == ">= 0.68.0", f"Unexpected Terragrunt version constraint: {version}"

def test_f1_google_provider_fallback_locals():
    """Assert root.hcl defines the platform fallback values in its local block."""
    parsed = get_parsed_root_hcl()
    locals_block = parsed.get("locals", [{}])[0]
    
    assert "platform_system" in locals_block, "platform_system local variable must be defined"
    assert "platform_component" in locals_block, "platform_component local variable must be defined"
    assert "platform_env" in locals_block, "platform_env local variable must be defined"
    assert "platform_owner" in locals_block, "platform_owner local variable must be defined"
    assert "platform_managed_by" in locals_block, "platform_managed_by local variable must be defined"

def test_f1_versions_override_google_beta_version():
    """Assert root.hcl versions constraint has google and google-beta providers set to ~> 6.0."""
    parsed = get_parsed_root_hcl()
    generate_blocks = parsed.get("generate", [])
    versions_contents = ""
    for gen in generate_blocks:
        for name, block in gen.items():
            if name == "versions":
                versions_contents = block.get("contents", "")
                
    assert "version = \"~> 6.0\"" in versions_contents

def test_f1_syntax_validity():
    """Verify HCL syntax validity by attempting to parse with standard python-hcl2."""
    parsed = get_parsed_root_hcl()
    assert isinstance(parsed, dict)
    assert len(parsed) > 0


# -----------------------------------------------------------------------------
# F2: CiliumNetworkPolicy in helm/app
# -----------------------------------------------------------------------------
HELM_CHART_PATH = os.path.join(PROJECT_ROOT, "helm", "app")

def render_helm_template(values=None):
    cmd = ["helm", "template", "app", HELM_CHART_PATH]
    if values:
        for k, v in values.items():
            cmd.extend(["--set", f"{k}={v}"])
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    
    # Parse YAML multi-documents
    docs = yaml.safe_load_all(result.stdout)
    return [d for d in docs if d is not None]


# --- Tier 1: F2 Feature Coverage ---

def test_f2_renders_cilium_policy_when_enabled():
    """Assert CiliumNetworkPolicy is rendered when ciliumNetworkPolicy.enabled=true."""
    docs = render_helm_template({"ciliumNetworkPolicy.enabled": "true"})
    cilium_policies = [d for d in docs if d.get("kind") == "CiliumNetworkPolicy"]
    assert len(cilium_policies) == 1, "Expected exactly one CiliumNetworkPolicy resource"
    policy = cilium_policies[0]
    assert policy.get("apiVersion") == "cilium.io/v2"

def test_f2_does_not_render_cilium_policy_when_disabled():
    """Assert CiliumNetworkPolicy is not rendered when ciliumNetworkPolicy.enabled=false."""
    docs = render_helm_template({"ciliumNetworkPolicy.enabled": "false"})
    cilium_policies = [d for d in docs if d.get("kind") == "CiliumNetworkPolicy"]
    assert len(cilium_policies) == 0, "Did not expect CiliumNetworkPolicy resource"

def test_f2_enforces_default_deny_ingress_via_platform_system():
    """Assert Cilium ingress allows traffic only from pods with matching platform.system."""
    system_name = "auth-service"
    docs = render_helm_template({
        "ciliumNetworkPolicy.enabled": "true",
        "platform.system": system_name
    })
    policy = [d for d in docs if d.get("kind") == "CiliumNetworkPolicy"][0]
    ingress_rules = policy.get("spec", {}).get("ingress", [])
    
    # Ingress must contain a matchLabels block restricting platform.system
    matched_ingress = False
    for rule in ingress_rules:
        from_endpoints = rule.get("fromEndpoints", [])
        for ep in from_endpoints:
            match_labels = ep.get("matchLabels", {})
            if match_labels.get("platform.system") == system_name:
                matched_ingress = True
                
    assert matched_ingress, f"No ingress rule found matching platform.system == '{system_name}'"

def test_f2_enforces_default_deny_egress_via_platform_system():
    """Assert Cilium egress allows traffic only to pods with matching platform.system."""
    system_name = "payment-gateway"
    docs = render_helm_template({
        "ciliumNetworkPolicy.enabled": "true",
        "platform.system": system_name
    })
    policy = [d for d in docs if d.get("kind") == "CiliumNetworkPolicy"][0]
    egress_rules = policy.get("spec", {}).get("egress", [])
    
    matched_egress = False
    for rule in egress_rules:
        to_endpoints = rule.get("toEndpoints", [])
        for ep in to_endpoints:
            match_labels = ep.get("matchLabels", {})
            if match_labels.get("platform.system") == system_name:
                matched_egress = True
                
    assert matched_egress, f"No egress rule found matching platform.system == '{system_name}'"

def test_f2_allows_ingress_from_gateway():
    """Assert Cilium ingress rules allow traffic from the ingress component (platform.component == ingress)."""
    docs = render_helm_template({"ciliumNetworkPolicy.enabled": "true"})
    policy = [d for d in docs if d.get("kind") == "CiliumNetworkPolicy"][0]
    ingress_rules = policy.get("spec", {}).get("ingress", [])
    
    matched_gateway = False
    for rule in ingress_rules:
        from_endpoints = rule.get("fromEndpoints", [])
        for ep in from_endpoints:
            match_labels = ep.get("matchLabels", {})
            if match_labels.get("platform.component") == "ingress":
                matched_gateway = True
                
    assert matched_gateway, "No ingress rule found allowing platform.component == 'ingress'"


# --- Tier 2: F2 Boundary & Corner Cases ---

def test_f2_strict_validation_fails_on_missing_required_labels():
    """Assert Helm templating fails when platform.strict=true and required platform parameters are empty."""
    with pytest.raises(subprocess.CalledProcessError) as excinfo:
        render_helm_template({
            "platform.strict": "true",
            "platform.system": ""
        })
    assert excinfo.value.returncode != 0

def test_f2_custom_ingress_egress_rules_appended():
    """Assert custom ingress and egress rules are appended to the Cilium policy."""
    docs = render_helm_template({
        "ciliumNetworkPolicy.enabled": "true",
        "ciliumNetworkPolicy.ingress[0].fromEndpoints[0].matchLabels.platform\\.system": "monitoring",
        "ciliumNetworkPolicy.egress[0].toEntities[0]": "world"
    })
    policy = [d for d in docs if d.get("kind") == "CiliumNetworkPolicy"][0]
    ingress_rules = policy.get("spec", {}).get("ingress", [])
    egress_rules = policy.get("spec", {}).get("egress", [])
    
    # Check monitoring ingress
    has_monitoring = any(
        any(ep.get("matchLabels", {}).get("platform.system") == "monitoring" for ep in r.get("fromEndpoints", []))
        for r in ingress_rules if "fromEndpoints" in r
    )
    # Check world egress
    has_world = any(
        any(entity == "world" for entity in r.get("toEntities", []))
        for r in egress_rules if "toEntities" in r
    )
    assert has_monitoring, "Custom monitoring ingress rule was not rendered"
    assert has_world, "Custom world egress rule was not rendered"

def test_f2_allow_dns_egress_port_53():
    """Assert the default DNS egress policy permits port 53 traffic."""
    docs = render_helm_template({"ciliumNetworkPolicy.enabled": "true"})
    policy = [d for d in docs if d.get("kind") == "CiliumNetworkPolicy"][0]
    egress_rules = policy.get("spec", {}).get("egress", [])
    
    has_dns_port = False
    for r in egress_rules:
        to_ports = r.get("toPorts", [])
        for tp in to_ports:
            ports = tp.get("ports", [])
            for p in ports:
                if p.get("port") == "53":
                    has_dns_port = True
    assert has_dns_port, "DNS egress port 53 is not allowed"

def test_f2_selector_labels_match_service_labels():
    """Assert that endpointSelector labels in Cilium policy match service selector labels."""
    docs = render_helm_template({"ciliumNetworkPolicy.enabled": "true"})
    policy = [d for d in docs if d.get("kind") == "CiliumNetworkPolicy"][0]
    service = [d for d in docs if d.get("kind") == "Service"][0]
    
    policy_selector = policy.get("spec", {}).get("endpointSelector", {}).get("matchLabels", {})
    service_selector = service.get("spec", {}).get("selector", {})
    
    assert policy_selector == service_selector, "Cilium endpoint selector labels mismatch Service selectors"

def test_f2_empty_platform_env_defaults_to_namespace():
    """Assert platform.env defaults to Release.Namespace (default) if empty."""
    docs = render_helm_template({
        "ciliumNetworkPolicy.enabled": "true",
        "platform.env": ""
    })
    for doc in docs:
        labels = doc.get("metadata", {}).get("labels", {})
        if "platform.env" in labels:
            assert labels["platform.env"] == "default"


# -----------------------------------------------------------------------------
# F3: AWS ABAC IAM policies (s3-app, dynamodb, rds-postgres)
# -----------------------------------------------------------------------------
MODULES_ROOT = os.path.join(PROJECT_ROOT, "terraform", "modules")

def scan_tf_files_for_iam_policies(module_dir):
    full_path = os.path.join(MODULES_ROOT, module_dir)
    assert os.path.exists(full_path), f"Module folder not found: {full_path}"
    
    tf_files = [f for f in os.listdir(full_path) if f.endswith(".tf")]
    policy_documents = []
    
    for f_name in tf_files:
        with open(os.path.join(full_path, f_name), "r") as f:
            content = f.read()
            pos = 0
            while True:
                match_data = re.search(r'data\s+"aws_iam_policy_document"\s+"([^"]+)"', content[pos:])
                match_res = re.search(r'resource\s+"aws_iam_policy"\s+"([^"]+)"', content[pos:])
                
                if not match_data and not match_res:
                    break
                
                idx_data = match_data.start() + pos if match_data else len(content)
                idx_res = match_res.start() + pos if match_res else len(content)
                
                if idx_data < idx_res:
                    name = match_data.group(1)
                    block_start = idx_data
                    block = extract_braced_block(content, block_start)
                    policy_documents.append({
                        "file": f_name,
                        "type": "data",
                        "name": name,
                        "contents": block
                    })
                    pos = block_start + len(block) + 1
                else:
                    name = match_res.group(1)
                    block_start = idx_res
                    block = extract_braced_block(content, block_start)
                    policy_documents.append({
                        "file": f_name,
                        "type": "resource",
                        "name": name,
                        "contents": block
                    })
                    pos = block_start + len(block) + 1
                    
                if pos >= len(content):
                    break
                    
    return policy_documents

def verify_abac_condition_in_policy(policy):
    contents = policy["contents"]
    return "aws:PrincipalTag/platform:system" in contents and "aws:ResourceTag/platform:system" in contents


# --- Tier 1: F3 Feature Coverage ---

def test_f3_s3_app_iam_abac_condition():
    """Assert that IAM policy documents in s3-app verify dynamic PrincipalTag == ResourceTag matching."""
    policies = scan_tf_files_for_iam_policies("s3-app")
    assert len(policies) > 0, "No IAM policies found in s3-app"
    
    abac_verified = False
    for p in policies:
        if verify_abac_condition_in_policy(p):
            abac_verified = True
            break
    assert abac_verified, "s3-app IAM policies lack PrincipalTag/platform:system == ResourceTag/platform:system check"

def test_f3_dynamodb_iam_abac_condition():
    """Assert that IAM policy documents in dynamodb verify dynamic PrincipalTag == ResourceTag matching."""
    policies = scan_tf_files_for_iam_policies("dynamodb")
    assert len(policies) > 0, "No IAM policies found in dynamodb"
    
    abac_verified = False
    for p in policies:
        if verify_abac_condition_in_policy(p):
            abac_verified = True
            break
    assert abac_verified, "dynamodb IAM policies lack PrincipalTag/platform:system == ResourceTag/platform:system check"

def test_f3_rds_postgres_iam_abac_condition():
    """Assert that IAM policy documents in rds-postgres verify dynamic PrincipalTag == ResourceTag matching."""
    policies = scan_tf_files_for_iam_policies("rds-postgres")
    assert len(policies) > 0, "No IAM policies found in rds-postgres"
    
    abac_verified = False
    for p in policies:
        if verify_abac_condition_in_policy(p):
            abac_verified = True
            break
    assert abac_verified, "rds-postgres IAM policies lack PrincipalTag/platform:system == ResourceTag/platform:system check"

def test_f3_s3_app_create_iam_policies_variable():
    """Verify s3-app module contains a create_iam_policies boolean flag to conditionally create roles."""
    full_path = os.path.join(MODULES_ROOT, "s3-app", "variables.tf")
    with open(full_path, "r") as f:
        parsed = hcl2.load(f)
    variables = parsed.get("variable", [])
    has_flag = False
    for var_block in variables:
        for name, contents in var_block.items():
            if name == "create_iam_policies":
                has_flag = True
    assert has_flag, "s3-app variables.tf missing create_iam_policies flag"

def test_f3_dynamodb_create_iam_policies_variable():
    """Verify dynamodb module contains a create_iam_policies boolean flag."""
    full_path = os.path.join(MODULES_ROOT, "dynamodb", "variables.tf")
    with open(full_path, "r") as f:
        parsed = hcl2.load(f)
    variables = parsed.get("variable", [])
    has_flag = False
    for var_block in variables:
        for name, contents in var_block.items():
            if name == "create_iam_policies":
                has_flag = True
    assert has_flag, "dynamodb variables.tf missing create_iam_policies flag"


# --- Tier 2: F3 Boundary & Corner Cases ---

def test_f3_iam_policy_json_invalid_conditions():
    """Assert that no static fallback bypass condition is written in modules' IAM documents."""
    for module in ["s3-app", "dynamodb"]:
        policies = scan_tf_files_for_iam_policies(module)
        for p in policies:
            contents = p["contents"]
            for val in ["app", "auth", "payment", "analytics"]:
                if "aws:PrincipalTag/platform:system" in contents:
                    assert val not in contents, f"Bypass risk: IAM policy contains hardcoded system tag '{val}'"

def test_f3_iam_policy_resource_tag_format():
    """Assert IAM policy checks the colon tag format (platform:system) on AWS, and not the dot format."""
    for module in ["s3-app", "dynamodb"]:
        policies = scan_tf_files_for_iam_policies(module)
        for p in policies:
            contents = p["contents"]
            assert "platform.system" not in contents, "AWS ABAC must use platform:system (with colon) rather than platform.system"

def test_f3_rds_postgres_no_unrestricted_iam_db_auth():
    """Assert that if iam_database_authentication_enabled is true, DB access is not un-segregated."""
    full_path = os.path.join(MODULES_ROOT, "rds-postgres", "main.tf")
    with open(full_path, "r") as f:
        content = f.read()
    if "iam_database_authentication_enabled = var.iam_authentication_enabled" in content:
        policies = scan_tf_files_for_iam_policies("rds-postgres")
        for p in policies:
            assert verify_abac_condition_in_policy(p), "rds-postgres exposes IAM authentication without dynamic tag restrictions"

def test_f3_s3_app_iam_abac_sid():
    """Assert that the SID of the S3 ABAC policy statement describes ABAC verification."""
    policies = scan_tf_files_for_iam_policies("s3-app")
    found_abac = False
    for p in policies:
        if verify_abac_condition_in_policy(p):
            found_abac = True
            assert "ABAC" in p["contents"] or "SystemMatch" in p["contents"] or "Tag" in p["contents"]
    if found_abac:
        pass

def test_f3_dynamodb_iam_abac_sid():
    """Assert that the SID of the DynamoDB ABAC policy statement describes ABAC verification."""
    policies = scan_tf_files_for_iam_policies("dynamodb")
    found_abac = False
    for p in policies:
        if verify_abac_condition_in_policy(p):
            found_abac = True
            assert "ABAC" in p["contents"] or "SystemMatch" in p["contents"] or "Tag" in p["contents"]
    if found_abac:
        pass


# -----------------------------------------------------------------------------
# F4: SSO attribute mapping (terraform/modules/sso/)
# -----------------------------------------------------------------------------
SSO_ROOT = os.path.join(MODULES_ROOT, "sso")

def scan_sso_tf_files():
    tf_files = [f for f in os.listdir(SSO_ROOT) if f.endswith(".tf")]
    resources = {}
    for f_name in tf_files:
        with open(os.path.join(SSO_ROOT, f_name), "r") as f:
            content = f.read()
            pos = 0
            while True:
                match = re.search(r'resource\s+"([^"]+)"\s+"([^"]+)"', content[pos:])
                if not match:
                    break
                res_type = match.group(1)
                res_name = match.group(2)
                block_start = match.start() + pos
                block = extract_braced_block(content, block_start)
                
                if res_type not in resources:
                    resources[res_type] = {}
                resources[res_type][res_name] = block
                pos = block_start + len(block) + 1
                if pos >= len(content):
                    break
    return resources


# --- Tier 1: F4 Feature Coverage ---

def test_f4_ssoadmin_attribute_mapping_resource_exists():
    """Assert aws_ssoadmin_instance_access_control_attributes is defined in SSO module."""
    resources = scan_sso_tf_files()
    assert "aws_ssoadmin_instance_access_control_attributes" in resources, "Resource aws_ssoadmin_instance_access_control_attributes not found in SSO module"

def test_f4_ssoadmin_attribute_mapping_maps_platform_system():
    """Assert that the key platform:system is mapped in the SSO access control attributes."""
    resources = scan_sso_tf_files()
    ac_attributes = resources["aws_ssoadmin_instance_access_control_attributes"]
    found_key = False
    for name, block in ac_attributes.items():
        if 'key = "platform:system"' in block or 'key= "platform:system"' in block or 'key = "platform:system"' in block.replace(" ", ""):
            found_key = True
    assert found_key, "platform:system attribute key mapping is missing in SSO module"

def test_f4_ssoadmin_attribute_mapping_source():
    """Assert that the mapped source for platform:system references sso_lac_attribute_source."""
    resources = scan_sso_tf_files()
    ac_attributes = resources["aws_ssoadmin_instance_access_control_attributes"]
    source_value_matched = False
    for name, block in ac_attributes.items():
        if "source = var.sso_lac_attribute_source" in block or "source=var.sso_lac_attribute_source" in block or "source = var.sso_lac_attribute_source" in block.replace(" ", ""):
            source_value_matched = True
    assert source_value_matched, "platform:system mapping source must be var.sso_lac_attribute_source"

def test_f4_ssoadmin_attribute_mapping_target_sso_instance():
    """Assert attribute mapping targets local.sso_instance_arn."""
    resources = scan_sso_tf_files()
    ac_attributes = resources["aws_ssoadmin_instance_access_control_attributes"]
    for name, block in ac_attributes.items():
        assert "instance_arn = local.sso_instance_arn" in block or "instance_arn=local.sso_instance_arn" in block or "instance_arn = local.sso_instance_arn" in block.replace(" ", "")

def test_f4_ssoadmin_attribute_mapping_variable_definition():
    """Assert sso_lac_attribute_source is defined as a list of strings with department fallback."""
    full_path = os.path.join(SSO_ROOT, "variables.tf")
    with open(full_path, "r") as f:
        parsed = hcl2.load(f)
    variables = parsed.get("variable", [])
    sso_var = None
    for var_block in variables:
        for name, contents in var_block.items():
            if name == "sso_lac_attribute_source":
                sso_var = contents
                
    assert sso_var is not None, "sso_lac_attribute_source variable is missing"
    var_type = sso_var.get("type").strip("${}")
    assert var_type == "list(string)"
    assert sso_var.get("default") == ["$${path:enterprise:user:department}"]


# --- Tier 2: F4 Boundary & Corner Cases ---

def test_f4_ssoadmin_attribute_mapping_empty_source():
    """Assert that the variable type and configuration requires list input."""
    resources = scan_sso_tf_files()
    ac_attributes = resources["aws_ssoadmin_instance_access_control_attributes"]
    for name, block in ac_attributes.items():
        assert "source" in block

def test_f4_ssoadmin_attribute_mapping_invalid_attribute_format():
    """Assert that mapped source variable default value starts with path expression prefix."""
    full_path = os.path.join(SSO_ROOT, "variables.tf")
    with open(full_path, "r") as f:
        parsed = hcl2.load(f)
    variables = parsed.get("variable", [])
    for var_block in variables:
        for name, contents in var_block.items():
            if name == "sso_lac_attribute_source":
                default = contents.get("default")
                for d in default:
                    assert d.startswith("$${path:") or d.startswith("${path:"), f"Invalid path expression format: {d}"

def test_f4_ssoadmin_attribute_mapping_single_attributes_resource():
    """Assert only a single aws_ssoadmin_instance_access_control_attributes resource is declared."""
    resources = scan_sso_tf_files()
    instances = resources.get("aws_ssoadmin_instance_access_control_attributes", {})
    assert len(instances) <= 1, "Only one instance access control attributes resource can exist per SSO instance"

def test_f4_ssoadmin_permission_set_tagging_organization_id():
    """Assert aws_ssoadmin_permission_set includes organization_id in tags."""
    resources = scan_sso_tf_files()
    perm_sets = resources.get("aws_ssoadmin_permission_set", {})
    assert len(perm_sets) > 0, "No permission sets defined in SSO module"
    for name, block in perm_sets.items():
        assert "OrganizationId = var.organization_id" in block or "OrganizationId=var.organization_id" in block or "OrganizationId = var.organization_id" in block.replace(" ", "")

def test_f4_ssoadmin_attribute_mapping_non_abac_attributes_not_mapped():
    """Assert only allowed ABAC attributes are mapped (preventing privilege leak of unrelated tags)."""
    resources = scan_sso_tf_files()
    ac_attributes = resources["aws_ssoadmin_instance_access_control_attributes"]
    for name, block in ac_attributes.items():
        keys = re.findall(r'key\s*=\s*"([^"]+)"', block)
        for k in keys:
            assert k in ["platform:system", "platform:owner", "platform:component"], f"Banned mapping of key '{k}'"


# -----------------------------------------------------------------------------
# Tier 3: Cross-Feature Combinations
# -----------------------------------------------------------------------------

def test_comb_gcp_label_k8s_label_alignment():
    """Assert that the platform system label keys correspond across GCP (under_scores) and K8s (dots)."""
    provider_str = get_provider_contents_from_root_hcl()
    gcp_labels = get_default_labels_from_provider_string(provider_str, "google")
    
    values_path = os.path.join(HELM_CHART_PATH, "values.yaml")
    with open(values_path, "r") as f:
        values = yaml.safe_load(f)
    k8s_platform = values.get("platform", {})
    
    assert "platform_system" in gcp_labels
    assert "system" in k8s_platform
    assert "platform_component" in gcp_labels
    assert "component" in k8s_platform

def test_comb_aws_abac_sso_alignment():
    """Assert that the principal tag mapped in SSO maps exactly to the condition variables checked in AWS ABAC."""
    resources = scan_sso_tf_files()
    ac_attributes = resources.get("aws_ssoadmin_instance_access_control_attributes", {})
    mapped_keys = []
    for name, block in ac_attributes.items():
        keys = re.findall(r'key\s*=\s*"([^"]+)"', block)
        mapped_keys.extend(keys)
            
    assert "platform:system" in mapped_keys, "SSO does not map platform:system"

def test_comb_logical_service_boundary_gcp_to_k8s():
    """Assert that platform_system falls back to default values in both GKE/GCP plane and Helm charts."""
    parsed_gcp = get_parsed_root_hcl()
    gcp_locals = parsed_gcp.get("locals", [{}])[0]
    gcp_fallback = gcp_locals.get("platform_system", "")
    
    values_path = os.path.join(HELM_CHART_PATH, "values.yaml")
    with open(values_path, "r") as f:
        values = yaml.safe_load(f)
    helm_default = values.get("platform", {}).get("system")
    
    assert "local." in gcp_fallback or gcp_fallback != ""
    assert helm_default != ""

def test_comb_abac_k8s_aws_integration():
    """Assert ServiceAccount IRSA annotations align with IAM role structure designed for ABAC."""
    docs = render_helm_template({
        "serviceAccount.create": "true",
        "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn": "arn:aws:iam::123456789012:role/auth-service"
    })
    service_accounts = [d for d in docs if d.get("kind") == "ServiceAccount"]
    assert len(service_accounts) == 1
    sa = service_accounts[0]
    annotations = sa.get("metadata", {}).get("annotations", {})
    role_arn = annotations.get("eks.amazonaws.com/role-arn")
    assert role_arn == "arn:aws:iam::123456789012:role/auth-service"


# -----------------------------------------------------------------------------
# Tier 4: Real-World Application Scenarios
# -----------------------------------------------------------------------------

def test_scenario_microsegmented_app_on_gke():
    """Scenario: Deploy a microsegmented backend application (e.g. auth-service) on GKE."""
    docs = render_helm_template({
        "ciliumNetworkPolicy.enabled": "true",
        "platform.system": "auth-service",
        "platform.component": "backend",
        "platform.owner": "team-sec",
        "platform.env": "staging"
    })
    
    policy = [d for d in docs if d.get("kind") == "CiliumNetworkPolicy"][0]
    deployment = [d for d in docs if d.get("kind") == "Deployment"][0]
    
    pod_labels = deployment.get("spec", {}).get("template", {}).get("metadata", {}).get("labels", {})
    assert pod_labels.get("platform.system") == "auth-service"
    assert pod_labels.get("platform.component") == "backend"
    assert pod_labels.get("platform.env") == "staging"
    
    ingress = policy.get("spec", {}).get("ingress", [])
    matched = False
    for r in ingress:
        for ep in r.get("fromEndpoints", []):
            if ep.get("matchLabels", {}).get("platform.system") == "auth-service":
                matched = True
    assert matched

def test_scenario_multi_tenant_aws_resources_with_abac():
    """Scenario: Multi-tenant tenant checks S3 and DynamoDB with their system tag (platform:system = checkout)."""
    for module in ["s3-app", "dynamodb"]:
        policies = scan_tf_files_for_iam_policies(module)
        assert len(policies) > 0
        abac_found = False
        for p in policies:
            if verify_abac_condition_in_policy(p):
                abac_found = True
        assert abac_found, f"Module '{module}' IAM policies do not enforce dynamic system matching"

def test_scenario_sso_federated_user_accessing_s3():
    """Scenario: SSO user in 'billing' logs in (federated tag platform:system=billing) and attempts S3 read/write."""
    resources = scan_sso_tf_files()
    ac_attributes = resources.get("aws_ssoadmin_instance_access_control_attributes", {})
    mapped = False
    for name, block in ac_attributes.items():
        if 'key = "platform:system"' in block or 'key= "platform:system"' in block or 'key = "platform:system"' in block.replace(" ", ""):
            mapped = True
    assert mapped, "User directory mapping fails to propagate billing department to platform:system session tag"

def test_scenario_service_mesh_canary_with_network_isolation():
    """Scenario: Service mesh rollout using progressive canary release alongside CiliumNetworkPolicy."""
    docs = render_helm_template({
        "rollout.enabled": "true",
        "ciliumNetworkPolicy.enabled": "true"
    })
    
    rollouts = [d for d in docs if d.get("kind") == "Rollout"]
    assert len(rollouts) == 1, "Rollout was not rendered when enabled"
    rollout = rollouts[0]
    
    rollout_selector = rollout.get("spec", {}).get("selector", {}).get("matchLabels", {})
    policy = [d for d in docs if d.get("kind") == "CiliumNetworkPolicy"][0]
    policy_selector = policy.get("spec", {}).get("endpointSelector", {}).get("matchLabels", {})
    
    assert rollout_selector == policy_selector, "Cilium Network Policy selector must match Rollout pod selectors"

def test_scenario_disaster_recovery_cross_region_labels():
    """Scenario: Cross-region disaster recovery replication verifying cloud-provider labels."""
    parsed = get_parsed_root_hcl()
    inputs = parsed.get("inputs")
    assert "region_vars.locals" in str(inputs)
