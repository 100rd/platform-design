terraform {
  required_version = "~> 1.11"

  required_providers {
    # Talos machine config — used to ASSERT the immutable-OS security posture
    # (no SSH, mTLS machine API, KubePrism) by re-rendering the machine config
    # and checking the posture fields. siderolabs/talos is the named provider in
    # the bare-metal plan §3 (DESIGN ONLY) and in WS-A's talos-machineconfig.
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.7"
    }

    # Kyverno / Gatekeeper policy bundle delivery as code (CRs applied to the
    # cluster). alekc/kubectl is the repo-pinned kubectl provider (see
    # terraform/modules/platform-crds/versions.tf).
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }
}
