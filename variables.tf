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
  description = "Path to the SSH public key file that will be registered on the cluster nodes."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key used by the kube-hetzner module to bootstrap k3s on the nodes via cloud-init / SSH. The key is never stored in Terraform state."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "cluster_name" {
  description = "Logical name for the cluster. Used as a prefix for Hetzner Cloud resource names (servers, networks, firewalls, load balancers)."
  type        = string
  default     = "opendesk-eval"
}

variable "control_plane_type" {
  description = <<-EOT
    Hetzner Cloud server type for the control-plane node.

    MUST be an x86/Intel instance — ARM (CAX/Ampere) is NOT supported by
    openDesk. Several openDesk container images and Python wheels ship x86-only
    binaries and will crash-loop on ARM nodes.

    The control-plane node only runs k3s system components (API server,
    scheduler, controller-manager, etcd). All openDesk workloads run on the
    agent nodes. cx22 (2 vCPU / 4 GB) is sufficient.
  EOT
  type        = string
  default     = "cx22"

  validation {
    condition     = !startswith(lower(var.control_plane_type), "cax")
    error_message = "ARM/Ampere instances (CAX prefix) are not supported by openDesk. Use an x86 type such as cx22."
  }
}

variable "agent_type" {
  description = <<-EOT
    Hetzner Cloud server type for the agent (worker) nodes.

    MUST be an x86/Intel instance — ARM (CAX/Ampere) is NOT supported by
    openDesk. Several openDesk container images and Python wheels ship x86-only
    binaries and will crash-loop on ARM nodes.

    cx33 provides 8 vCPU / 16 GB RAM per node. With the default 3 agents the
    cluster has 24 vCPU / 48 GB available for workloads — well above the
    openDesk evaluation minimum of 12 vCPU / 32 GB.
  EOT
  type        = string
  default     = "cx33"

  validation {
    condition     = !startswith(lower(var.agent_type), "cax")
    error_message = "ARM/Ampere instances (CAX prefix) are not supported by openDesk. Use an x86 type such as cx33."
  }
}

variable "agent_count" {
  description = "Number of agent (worker) nodes. Three cx33 nodes provide 24 vCPU / 48 GB, comfortably above the openDesk evaluation minimum of 12 vCPU / 32 GB."
  type        = number
  default     = 3
}

variable "lb_type" {
  description = "Hetzner Load Balancer type for the ingress LB. lb11 (5 Gbit/s, 25 targets) is sufficient for an evaluation cluster."
  type        = string
  default     = "lb11"
}

variable "location" {
  description = "Hetzner Cloud datacenter location for the nodes, network, and load balancer."
  type        = string
  default     = "nbg1"
}

variable "base_domain" {
  description = "Base domain for the openDesk deployment. Terraform creates A records for '{base_domain}' and '*.{base_domain}'. Must be a subdomain of cloudflare_zone_name."
  type        = string
  default     = "od.heinle.cc"
}
