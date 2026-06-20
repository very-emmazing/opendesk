terraform {
  # v2.19.0 of kube-hetzner raised the minimum Terraform version to 1.10.1
  # (switched from null_resource to terraform_data with automatic state migration).
  required_version = ">= 1.10.1"

  required_providers {
    # Hetzner Cloud: minimum 1.59.0 required by kube-hetzner v2.19+
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.59.0, < 2.0.0"
    }

    # Pinned to v4.x — Cloudflare v5 renamed cloudflare_record to
    # cloudflare_dns_record, a breaking change we defer until the provider v5
    # migration tooling (tf-migrate) matures.
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }

    # alekc/kubectl is the actively maintained fork of gavinbunney/kubectl.
    # We use it instead of kubernetes_manifest for the ClusterIssuer because
    # kubernetes_manifest validates against the CRD schema at plan time; if
    # cert-manager hasn't been installed yet the plan fails. kubectl_manifest
    # skips schema validation and applies the raw YAML, making it safe to use
    # in a single terraform apply with proper depends_on chaining.
    # GitHub repo: github.com/alekc/terraform-provider-kubectl
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# ── Hetzner Cloud ─────────────────────────────────────────────────────────────
provider "hcloud" {
  token = var.hcloud_token
}

# ── Cloudflare ────────────────────────────────────────────────────────────────
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ── Kubernetes / Helm / Kubectl ───────────────────────────────────────────────
# These providers are configured from the kube-hetzner module output
# (kubeconfig_data), which is only available AFTER the cluster has been created.
#
# On a fresh Terraform state (no cluster yet), a plain `terraform plan` will
# error because these providers cannot connect. Use the two-phase approach
# documented in README.md:
#
#   Phase 1 — create the cluster:
#     terraform apply -target=module.kube_hetzner -target=local_sensitive_file.kubeconfig
#
#   Phase 2 — apply all add-ons:
#     terraform apply
#
# For a plan-only review you can target just the hcloud resources:
#   terraform plan -target=module.kube_hetzner

provider "kubernetes" {
  host                   = module.kube_hetzner.kubeconfig_data.host
  cluster_ca_certificate = module.kube_hetzner.kubeconfig_data.cluster_ca_certificate
  client_certificate     = module.kube_hetzner.kubeconfig_data.client_certificate
  client_key             = module.kube_hetzner.kubeconfig_data.client_key
}

# Helm provider v3 moved the kubernetes connection from a nested block to an
# object argument (breaking change from v2). Use assignment syntax, not block.
provider "helm" {
  kubernetes = {
    host                   = module.kube_hetzner.kubeconfig_data.host
    cluster_ca_certificate = module.kube_hetzner.kubeconfig_data.cluster_ca_certificate
    client_certificate     = module.kube_hetzner.kubeconfig_data.client_certificate
    client_key             = module.kube_hetzner.kubeconfig_data.client_key
  }
}

provider "kubectl" {
  host                   = module.kube_hetzner.kubeconfig_data.host
  cluster_ca_certificate = module.kube_hetzner.kubeconfig_data.cluster_ca_certificate
  client_certificate     = module.kube_hetzner.kubeconfig_data.client_certificate
  client_key             = module.kube_hetzner.kubeconfig_data.client_key
  load_config_file       = false
}
