# ── Kubernetes API connection (from cluster module via Terragrunt dependency) ──
variable "kube_host" {
  description = "Kubernetes API server URL. Supplied by the cluster module output kube_host."
  type        = string
}

variable "kube_cluster_ca_certificate" {
  description = "Base64 PEM cluster CA certificate. Supplied by the cluster module output kube_cluster_ca_certificate."
  type        = string
  sensitive   = true
}

variable "kube_client_certificate" {
  description = "Base64 PEM client certificate. Supplied by the cluster module output kube_client_certificate."
  type        = string
  sensitive   = true
}

variable "kube_client_key" {
  description = "Base64 PEM client private key. Supplied by the cluster module output kube_client_key."
  type        = string
  sensitive   = true
}

# ── Hetzner Load Balancer references (from cluster module) ─────────────────────
variable "lb_id" {
  description = "ID of the Hetzner Load Balancer. Applied to haproxy-ingress via the load-balancer.hetzner.cloud/id Service annotation so CCM binds the Service to the pre-provisioned LB."
  type        = string
}

variable "lb_ipv4" {
  description = "Public IPv4 address of the Hetzner Load Balancer. Used as the target of the Cloudflare A records."
  type        = string
}

# ── Cloudflare / cert-manager ──────────────────────────────────────────────────
variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone.DNS:Edit scoped to heinle.cc. Used both for cert-manager's DNS-01 ACME solver and for creating the DNS records. Pass via TF_VAR_cloudflare_api_token (never commit it)."
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

variable "base_domain" {
  description = "Base domain for the openDesk deployment. Creates A records for '{base_domain}' and '*.{base_domain}'. Must be a subdomain of cloudflare_zone_name."
  type        = string
  default     = "od.heinle.cc"
}

variable "letsencrypt_email" {
  description = "Email address for the Let's Encrypt ACME account. Receives certificate expiry warnings."
  type        = string
}
