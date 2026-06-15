# Project History

Auto-generated activity log. Newest entries at the bottom.


---
## [2026-06-15 19:42:33] terraform-engineer: 2nd-round AWS review-nit hardening

**Action**: implementation
**Category**: infrastructure

### What Was Done
Applied three independent 2nd-round review findings on the AWS GPU ML platform (branch fix/aws-review-nits, off main): (1) removed an erroneous /project/platform-design/ segment from the terraform source path in the aws-ml-abac-iam and aws-ml-scp-parity catalog units (broke terragrunt init); (2) in aws-ml-artifact-store converted the inline aws_iam_role_policy to a standalone aws_iam_policy + aws_iam_role_policy_attachment (CIS AWS 1.16) and added an aws_s3_bucket_policy with a DenyInsecureTransport statement (CIS AWS 2.1.1), keeping the public-access block; (3) hardened the aws-eks-gpu-dcgm auto-taint CronJob container with a restricted security_context (run_as_non_root, read_only_root_filesystem, no priv-esc, drop ALL caps) plus pod-level non-root/seccomp and var-driven resource requests/limits. Updated both modules' tftest.hcl with assertions for the new resources.

### Reasoning
Source-path bug was a real terragrunt init breaker (old path absent on disk). IAM/S3-TLS and CronJob hardening close CIS gaps flagged in review. Everything stays apply-gated / default-OFF. Did not touch aws-eks-inference-gateway (separate PR).

### Files Changed
- Modified: catalog/units/aws-ml-abac-iam/terragrunt.hcl, catalog/units/aws-ml-scp-parity/terragrunt.hcl, terraform/modules/aws-ml-artifact-store/main.tf, terraform/modules/aws-ml-artifact-store/aws-ml-artifact-store.tftest.hcl, terraform/modules/aws-eks-gpu-dcgm/main.tf, terraform/modules/aws-eks-gpu-dcgm/variables.tf, terraform/modules/aws-eks-gpu-dcgm/aws-eks-gpu-dcgm.tftest.hcl

### Outcome
✅ Completed - fmt clean; artifact-store test 20/20, dcgm test 6/6; checkov dcgm 5/0, artifact-store 10/1 (the 1 = pre-existing CKV2_AWS_62 S3 event-notifications, out of scope); source paths resolve. Draft PR opened, not merged.

### Follow-up
- [ ] Reviewer merge after CI (tflint runs in CI; not installed locally)

**Tags**: #aws #terraform #cis #iam #s3 #dcgm #review-fixes #apply-gated
---
