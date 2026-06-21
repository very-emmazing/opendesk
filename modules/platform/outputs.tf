output "portal_url" {
  description = "Expected URL of the openDesk portal once helmfile apply completes. Not reachable until the helmfile step has run."
  value       = "https://portal.${var.base_domain}"
}

output "ingress_lb_ipv4" {
  description = "Public IPv4 of the Hetzner Load Balancer that the DNS records resolve to."
  value       = var.lb_ipv4
}

output "dns_records" {
  description = "Cloudflare A records created for the openDesk base domain."
  value = [
    cloudflare_record.apex.hostname,
    cloudflare_record.wildcard.hostname,
  ]
}
