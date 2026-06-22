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
    kube_host = "https://127.0.0.1:6443"
    # kube_hetzner returns base64decode(kubeconfig cert data), so mock values
    # must be raw PEM strings — the kubernetes/helm/kubectl providers validate
    # PEM format at provider init even during plan.
    kube_cluster_ca_certificate = <<-PEM
      -----BEGIN CERTIFICATE-----
      MIIBdDCCARmgAwIBAgIUYPPIn0nsMNw1pE/eNf12sw2WwXMwCgYIKoZIzj0EAwIw
      DzENMAsGA1UEAwwEbW9jazAeFw0yNjA2MjExOTQ3MDZaFw0zNjA2MTgxOTQ3MDZa
      MA8xDTALBgNVBAMMBG1vY2swWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARFobFp
      D4PfA3v7ecXgRaw9Au/eFb5RBYvJ6DgGELOZrG1PbH0ztObrMSplSXyrXczK/DA1
      UIHrdNK+yCY0tVjbo1MwUTAdBgNVHQ4EFgQUlt2K1thUe9WxxQm0vgxREzXuVxUw
      HwYDVR0jBBgwFoAUlt2K1thUe9WxxQm0vgxREzXuVxUwDwYDVR0TAQH/BAUwAwEB
      /zAKBggqhkjOPQQDAgNJADBGAiEAu8SDGncgJ8dM30TOZopRjBZoQfftlKBxE3Tv
      +yongmwCIQCejt9UeYhk4/CjSXdQX/KUcuSo7WpdZAb/u9n8tOKQEA==
      -----END CERTIFICATE-----
    PEM
    kube_client_certificate = <<-PEM
      -----BEGIN CERTIFICATE-----
      MIIBdDCCARmgAwIBAgIUYPPIn0nsMNw1pE/eNf12sw2WwXMwCgYIKoZIzj0EAwIw
      DzENMAsGA1UEAwwEbW9jazAeFw0yNjA2MjExOTQ3MDZaFw0zNjA2MTgxOTQ3MDZa
      MA8xDTALBgNVBAMMBG1vY2swWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARFobFp
      D4PfA3v7ecXgRaw9Au/eFb5RBYvJ6DgGELOZrG1PbH0ztObrMSplSXyrXczK/DA1
      UIHrdNK+yCY0tVjbo1MwUTAdBgNVHQ4EFgQUlt2K1thUe9WxxQm0vgxREzXuVxUw
      HwYDVR0jBBgwFoAUlt2K1thUe9WxxQm0vgxREzXuVxUwDwYDVR0TAQH/BAUwAwEB
      /zAKBggqhkjOPQQDAgNJADBGAiEAu8SDGncgJ8dM30TOZopRjBZoQfftlKBxE3Tv
      +yongmwCIQCejt9UeYhk4/CjSXdQX/KUcuSo7WpdZAb/u9n8tOKQEA==
      -----END CERTIFICATE-----
    PEM
    kube_client_key = <<-PEM
      -----BEGIN PRIVATE KEY-----
      MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQga1HP3LDAh8RYvRNh
      8NdpopEWEqIOIVYh9AnjnLfviSKhRANCAARFobFpD4PfA3v7ecXgRaw9Au/eFb5R
      BYvJ6DgGELOZrG1PbH0ztObrMSplSXyrXczK/DA1UIHrdNK+yCY0tVjb
      -----END PRIVATE KEY-----
    PEM
    network_id      = "0"
    lb_id           = "0"
    lb_ipv4         = "203.0.113.1" # TEST-NET-3 placeholder
    cluster_name    = "opendesk-eval"
    kubeconfig_path = "/tmp/kubeconfig.yaml"
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
