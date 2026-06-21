# ═════════════════════════════════════════════════════════════════════════════
# Unit: platform
#
# Installs the in-cluster add-ons (haproxy-ingress, cert-manager + the
# letsencrypt-dns ClusterIssuer) and the Cloudflare DNS records.
#
# The `dependency "cluster"` block makes Terragrunt apply the cluster unit
# first and feeds its outputs in as inputs here. This is what replaces the old
# two-phase `terraform apply -target=...` workflow: the kubernetes / helm /
# kubectl providers receive a live API endpoint because the cluster already
# exists by the time this unit runs.
# ═════════════════════════════════════════════════════════════════════════════

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules/platform"
}

dependency "cluster" {
  config_path = "../cluster"

  # Mock values let `terragrunt plan/validate` run on the platform unit before
  # the cluster has been applied (e.g. in CI). They are never used during a real
  # apply, where the actual cluster outputs are read instead.
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "fmt"]
  mock_outputs = {
    kube_host                   = "https://127.0.0.1:6443"
    kube_cluster_ca_certificate = "bW9jaw==" # base64("mock")
    kube_client_certificate     = "bW9jaw=="
    kube_client_key             = "bW9jaw=="
    network_id                  = "0"
    lb_id                       = "0"
    lb_ipv4                     = "203.0.113.1" # TEST-NET-3 placeholder
    cluster_name                = "opendesk-eval"
    kubeconfig_path             = "/tmp/kubeconfig.yaml"
  }
}

inputs = {
  kube_host                   = dependency.cluster.outputs.kube_host
  kube_cluster_ca_certificate = dependency.cluster.outputs.kube_cluster_ca_certificate
  kube_client_certificate     = dependency.cluster.outputs.kube_client_certificate
  kube_client_key             = dependency.cluster.outputs.kube_client_key

  lb_id   = dependency.cluster.outputs.lb_id
  lb_ipv4 = dependency.cluster.outputs.lb_ipv4
}
