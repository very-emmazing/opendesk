# ═════════════════════════════════════════════════════════════════════════════
# platform module — provider requirements
#
# Installs the in-cluster add-ons (haproxy-ingress, cert-manager + ClusterIssuer)
# and the Cloudflare DNS records. The kubernetes / helm / kubectl providers are
# configured from the cluster module's outputs, wired in by the Terragrunt
# dependency block in live/platform/terragrunt.hcl.
#
# Compatible with OpenTofu >= 1.8 and Terraform >= 1.10.1. Project standard is
# OpenTofu (driven by Terragrunt via terraform_binary = "tofu").
# ═════════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.8.0"

  required_providers {
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
    # with proper depends_on chaining.
    # GitHub repo: github.com/alekc/terraform-provider-kubectl
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
  }
}
