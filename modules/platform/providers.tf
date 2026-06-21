# ═════════════════════════════════════════════════════════════════════════════
# Provider configuration for the platform module.
#
# The kubernetes / helm / kubectl providers connect to the cluster created by
# the cluster module. The connection details arrive as input variables, which
# Terragrunt populates from the cluster module's outputs (see the dependency
# block in live/platform/terragrunt.hcl). Because the cluster already exists by
# the time this module runs, there is no two-phase apply / -target dance.
# ═════════════════════════════════════════════════════════════════════════════

provider "kubernetes" {
  host                   = var.kube_host
  cluster_ca_certificate = var.kube_cluster_ca_certificate
  client_certificate     = var.kube_client_certificate
  client_key             = var.kube_client_key
}

# Helm provider v3 moved the kubernetes connection from a nested block to an
# object argument (breaking change from v2). Use assignment syntax, not block.
provider "helm" {
  kubernetes = {
    host                   = var.kube_host
    cluster_ca_certificate = var.kube_cluster_ca_certificate
    client_certificate     = var.kube_client_certificate
    client_key             = var.kube_client_key
  }
}

provider "kubectl" {
  host                   = var.kube_host
  cluster_ca_certificate = var.kube_cluster_ca_certificate
  client_certificate     = var.kube_client_certificate
  client_key             = var.kube_client_key
  load_config_file       = false
}

# ── Cloudflare ────────────────────────────────────────────────────────────────
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
