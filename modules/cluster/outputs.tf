# ═════════════════════════════════════════════════════════════════════════════
# Outputs consumed by the platform module (via a Terragrunt dependency block)
# and by the operator.
# ═════════════════════════════════════════════════════════════════════════════

# ── Kubernetes API connection details ─────────────────────────────────────────
# The platform module configures its kubernetes / helm / kubectl providers from
# these four values. Splitting them into discrete outputs (rather than passing
# the whole kubeconfig_data object) keeps the dependency wiring explicit.
output "kube_host" {
  description = "Kubernetes API server URL."
  value       = module.kube_hetzner.kubeconfig_data.host
}

output "kube_cluster_ca_certificate" {
  description = "Base64 PEM cluster CA certificate for the Kubernetes API."
  value       = module.kube_hetzner.kubeconfig_data.cluster_ca_certificate
  sensitive   = true
}

output "kube_client_certificate" {
  description = "Base64 PEM client certificate for authenticating to the Kubernetes API."
  value       = module.kube_hetzner.kubeconfig_data.client_certificate
  sensitive   = true
}

output "kube_client_key" {
  description = "Base64 PEM client private key for authenticating to the Kubernetes API."
  value       = module.kube_hetzner.kubeconfig_data.client_key
  sensitive   = true
}

# ── Hetzner infrastructure references ─────────────────────────────────────────
output "network_id" {
  description = "ID of the cluster's Hetzner private network."
  value       = module.kube_hetzner.network_id
}

output "lb_id" {
  description = "ID of the Hetzner Load Balancer. The platform module passes this to haproxy-ingress via the load-balancer.hetzner.cloud/id Service annotation."
  value       = hcloud_load_balancer.ingress.id
}

output "lb_ipv4" {
  description = "Public IPv4 address of the Hetzner Load Balancer. DNS records for *.od.heinle.cc and od.heinle.cc point here."
  value       = hcloud_load_balancer.ingress.ipv4
}

output "cluster_name" {
  description = "Name of the Hetzner Cloud cluster (used as prefix for Hetzner resources)."
  value       = module.kube_hetzner.cluster_name
}

output "kubeconfig_path" {
  description = "Absolute path to the cluster kubeconfig written to disk. Export as KUBECONFIG before running kubectl or helmfile."
  value       = local_sensitive_file.kubeconfig.filename
}
