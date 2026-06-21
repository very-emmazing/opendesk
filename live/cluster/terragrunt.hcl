# ═════════════════════════════════════════════════════════════════════════════
# Unit: cluster
#
# Creates the Hetzner infrastructure: k3s nodes, private network, firewall, and
# the ingress Load Balancer, then writes the kubeconfig. Apply this first
# (Terragrunt does so automatically — the platform unit depends on it).
# ═════════════════════════════════════════════════════════════════════════════

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules/cluster"
}

inputs = {
  # Write the kubeconfig to a stable path at the repo root (NOT inside the
  # .terragrunt-cache copy, which is rebuilt on every run). Export this as
  # KUBECONFIG for kubectl / helmfile after apply.
  kubeconfig_path = "${get_repo_root()}/kubeconfig.yaml"
}
