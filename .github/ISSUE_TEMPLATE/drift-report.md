---
name: Infrastructure Drift Report
about: Report infrastructure drift detected between Terraform state and live cloud resources
title: "[Drift] Infrastructure drift detected in `<environment>` (<N> unit(s))"
labels: drift, automated
assignees: ""
---

## Infrastructure Drift Detected

**Environment**: `<environment>`
**Detected at**: <!-- ISO 8601 timestamp -->
**Workflow run**: [View run](<link>)
**Units with drift**: <!-- number -->

---

## Drifted Units

### `<unit-path>`

- **Add**: 0  **Change**: 0  **Destroy**: 0

Changed resources:
- `update` `<resource_address>`

---

## Root Cause

<!-- Fill in after investigation -->
- [ ] Manual change in AWS console
- [ ] External automation (Karpenter, Cluster Autoscaler, etc.)
- [ ] AWS service-initiated change
- [ ] Expired resource (certificate, token)
- [ ] Unknown

---

## Remediation Steps

> Choose the appropriate path based on your investigation.

### Option A: Re-apply to restore desired state (unintentional drift)

```bash
# Navigate to the drifted unit
cd terragrunt/<environment>/<region>/<unit>

# Review what will change
terragrunt plan

# Apply to reconcile
terragrunt apply
```

### Option B: Import and update code to match live state (intentional change)

```bash
# Import the live resource into Terraform state
terraform import <resource_type>.<name> <resource_id>

# Update the Terraform code to match
# Then verify no further changes
terraform plan  # should show: No changes
```

### Option C: Drift is expected — suppress for this resource

Add a `lifecycle` block to the Terraform resource:

```hcl
resource "aws_instance" "example" {
  # ...

  lifecycle {
    ignore_changes = [
      # Suppress drift for fields managed externally
      tags["ManagedBy"],
    ]
  }
}
```

---

## Verification

After remediation, verify the fix:

```bash
# Run plan — should show zero changes
terragrunt plan -detailed-exitcode
# Exit code 0 = clean, 2 = still drifted
```

Close this issue once plan shows no changes.

---

## References

- [Drift Detection Workflow](.github/workflows/drift-detection.yml)
- [Terragrunt Apply Workflow](.github/workflows/terragrunt-apply.yml)
- [Platform Infrastructure Runbook](docs/)

---
*This issue template is used by the automated drift detection workflow.*
*Manual reports: use this template to document manually discovered drift.*
