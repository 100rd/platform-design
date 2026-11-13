# ec2-declarative-policies

AWS Organizations **EC2 Declarative Policy** (`DECLARATIVE_POLICY_EC2`) — ADR-0017 Decision item 2.

Expresses *desired state* for the EC2 control plane, enforced at the API layer org-wide,
replacing brittle deny-SCP + Config-rule pairs. Enforced settings:

| Control | Setting | Default |
|---------|---------|---------|
| IMDSv2 required | `instance_metadata_defaults.http_tokens = required` (hop limit 2) | on |
| Block public EBS snapshots | `snapshot_block_public_access = block_new_sharing` | on |
| Block public AMIs | `image_block_public_access = block_new_sharing` | on |
| Allowed-AMI providers | `allowed_images_settings` (`audit_mode` → `enabled`) | `audit_mode`, `["amazon"]` |

Declarative policies use the `@@assign` inheritance operator (not IAM policy language).

## Prerequisites
- `DECLARATIVE_POLICY_EC2` must be in the organization's `enabled_policy_types`
  (added in `terragrunt/_org/_global/organization`).

## Staged rollout (ADR-0017 steps 3–4)
1. **Stage** — attach to the **Policy-Staging OU only**, `allowed_images_state = audit_mode`
   (log-only). Verify no legitimate launches break.
2. **Promote** — append the org **root id** to `target_ou_ids` (additive `for_each`) and
   flip `allowed_images_state` to `enabled`.
3. **Retire** the `require_imdsv2` SCP once IMDSv2 is enforced here at root (returns an SCP slot).

**Rollback:** drop the root id from `target_ou_ids` (revert to staged-only), or empty it
entirely (policy stays defined-but-unattached).

## Usage
```hcl
module "ec2_declarative" {
  source        = "../../terraform/modules/ec2-declarative-policies"
  target_ou_ids = [dependency.organization.outputs.policy_staging_ou_id]  # stage first
  # allowed_images_state = "enabled"  # flip after soak
  tags = { ManagedBy = "terragrunt", ADR = "0017" }
}
```

## References
- ADR-0017 §Decision item 2 · Epic #252 · follow-up #315
- AWS Organizations declarative policies (EC2): <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html>
