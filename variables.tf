variable "hcloud_token" {
  description = "Hetzner Cloud API token (Read & Write scope). Create at https://console.hetzner.cloud → Security → API Tokens. Pass via TF_VAR_hcloud_token or terraform.tfvars."
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone.DNS:Edit permission scoped to heinle.cc. Needed both for cert-manager DNS-01 ACME solver and for Terraform to create DNS records. Pass via TF_VAR_cloudflare_api_token."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for heinle.cc. Find it on the Cloudflare dashboard: Overview → API section (right sidebar) → Zone ID."
  type        = string
}

variable "cloudflare_zone_name" {
  description = "Root domain name of the Cloudflare zone. Must be the parent of base_domain."
  type        = string
  default     = "heinle.cc"
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt ACME account. Receives certificate expiry warnings."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file that will be registered on the cluster node."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key used by the kube-hetzner module to bootstrap k3s on the node via cloud-init / SSH. The key is never stored in Terraform state."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "cluster_name" {
  description = "Logical name for the cluster. Used as a prefix for Hetzner Cloud resource names (servers, networks, firewalls)."
  type        = string
  default     = "opendesk-eval"
}

variable "node_type" {
  description = <<-EOT
    Hetzner Cloud server type for the single control-plane node.

    MUST be an x86/Intel instance — ARM (CAX/Ampere) is NOT supported by
    openDesk. Several openDesk container images and Python wheels ship x86-only
    binaries and will crash-loop on ARM nodes.

    CCX43 provides 16 dedicated vCPU / 64 GB RAM, comfortably above the
    openDesk evaluation minimum of 12 vCPU / 32 GB RAM.
  EOT
  type        = string
  default     = "ccx43"

  validation {
    condition     = !startswith(lower(var.node_type), "cax")
    error_message = "ARM/Ampere instances (CAX prefix) are not supported by openDesk. Use an x86 type such as ccx43."
  }
}

variable "location" {
  description = "Hetzner Cloud datacenter location for the node and private network."
  type        = string
  default     = "nbg1"
}

variable "base_domain" {
  description = "Base domain for the openDesk deployment. Terraform creates A records for '{base_domain}' and '*.{base_domain}'. Must be a subdomain of cloudflare_zone_name."
  type        = string
  default     = "od.heinle.cc"
}
