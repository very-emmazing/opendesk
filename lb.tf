# ═════════════════════════════════════════════════════════════════════════════
# Hetzner Cloud Load Balancer — ingress
#
# Pre-provisioning the LB in Terraform gives us a stable public IP before
# the cluster is created. haproxy-ingress is deployed with
# service.type=LoadBalancer and the annotation
# load-balancer.hetzner.cloud/id pointing at this LB. The Hetzner cloud
# controller manager (CCM) then manages LB targets (the agent nodes) and
# port maps (80 and 443 → haproxy NodePorts) automatically.
#
# The LB is attached to the cluster's private network so CCM can route
# health checks and forwarded traffic via private IPs. This avoids exposing
# NodePort range ports on the nodes' public interfaces and removes the need
# for port 80/443 firewall rules on individual nodes.
# ═════════════════════════════════════════════════════════════════════════════

resource "hcloud_load_balancer" "ingress" {
  name               = "${var.cluster_name}-ingress"
  load_balancer_type = var.lb_type
  location           = var.location

  labels = {
    cluster = var.cluster_name
    role    = "ingress"
  }
}

# Attach the LB to the cluster's private network.
# CCM reads this attachment to forward traffic via private node IPs.
# Must be created after the cluster (and its network) exist.
resource "hcloud_load_balancer_network" "ingress" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  network_id       = module.kube_hetzner.network_id

  depends_on = [module.kube_hetzner]
}
