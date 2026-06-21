# ═════════════════════════════════════════════════════════════════════════════
# Cloudflare DNS records for openDesk
#
# Both records point at the Hetzner Load Balancer's public IP (var.lb_ipv4,
# supplied by the cluster module). The LB distributes HTTPS traffic to
# haproxy-ingress pods across agent nodes.
#
# proxied = false is MANDATORY for two reasons:
#   1. Let's Encrypt DNS-01 ACME challenge: cert-manager reads TXT records
#      directly via recursive DNS. Cloudflare's proxy layer rewrites certain
#      DNS responses and can interfere with TXT record propagation, causing
#      certificate issuance to fail.
#   2. WebSocket connections: Several openDesk services (Collabora Online,
#      Nextcloud Talk, Element) use long-lived WebSocket connections. The free
#      Cloudflare proxy has a 100-second WebSocket timeout that breaks these.
# ═════════════════════════════════════════════════════════════════════════════

locals {
  # The Hetzner Load Balancer's public IP, created in the cluster module and
  # passed in via the Terragrunt dependency. A stable address independent of
  # individual node IPs or rescheduling events.
  ingress_ip = var.lb_ipv4

  # Derive the subdomain label relative to the Cloudflare zone.
  # Example: base_domain="od.heinle.cc", zone="heinle.cc" → subdomain="od"
  # Cloudflare appends the zone name automatically; record names must be
  # relative (e.g. "od", not "od.heinle.cc").
  subdomain = trimsuffix(var.base_domain, ".${var.cloudflare_zone_name}")
}

# Wildcard A record: *.od.heinle.cc → LB IP
# Catches all openDesk sub-services: portal.od.heinle.cc, mail.od.heinle.cc, etc.
resource "cloudflare_record" "wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*.${local.subdomain}"
  content = local.ingress_ip
  type    = "A"
  proxied = false
  ttl     = 300
}

# Apex A record: od.heinle.cc → LB IP
# Required for the openDesk portal to be reachable at the bare base domain.
resource "cloudflare_record" "apex" {
  zone_id = var.cloudflare_zone_id
  name    = local.subdomain
  content = local.ingress_ip
  type    = "A"
  proxied = false
  ttl     = 300
}
