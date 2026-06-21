# ═════════════════════════════════════════════════════════════════════════════
# cluster module — provider requirements
#
# This module creates the Hetzner infrastructure only (nodes, network, firewall,
# Load Balancer) and writes the kubeconfig. It deliberately does NOT depend on
# the kubernetes / helm / kubectl providers — those belong to the platform
# module, which runs after this one (see live/platform).
#
# Compatible with OpenTofu >= 1.8 and Terraform >= 1.10.1. The project standard
# is OpenTofu (driven by Terragrunt via terraform_binary = "tofu").
# ═════════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.8.0"

  required_providers {
    # Hetzner Cloud: minimum 1.59.0 required by kube-hetzner v2.19+
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.59.0, < 2.0.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}
