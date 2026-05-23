# hello-world (Creme-ala-creme)

GitOps deployment manifest for the `hello-world` application owned by
[`100rd/Creme-ala-creme`](https://github.com/100rd/Creme-ala-creme).

## Update flow

1. A push to `main` in `Creme-ala-creme` builds the image, pushes it,
   and captures the resulting `sha256:...` digest.
2. The `gitops-pr` job in that repo opens a PR here updating
   `helmrelease.yaml`:
   - `spec.values.image.repository` ← canonical ECR URL
   - `spec.values.image.digest`     ← new sha256 digest
   - `spec.values.image.tag`        ← cleared (digest wins)
3. A human reviewer (or branch protection auto-merge) merges that PR.
4. Flux reconciles the HelmRelease and rolls out the new digest.

## Rollback

Revert the PR that introduced the digest you want to back out. Flux
reconciles the older digest on the next interval.
