# ═════════════════════════════════════════════════════════════════════════════
# haproxy-ingress  (community controller — jcmoraisjr)
# Chart: https://haproxy-ingress.github.io/charts  v0.16.1
#
# openDesk's documentation recommends haproxy-ingress as the ingress
# controller. Two global tuning parameters MUST be set or certain openDesk
# components will return 400 Bad Request errors:
#
#   tune.bufsize 65536
#     HAProxy's default internal buffer is 16 KB. openDesk components
#     (Collabora Online, Nextcloud) send Cookie and Authorization headers
#     that can exceed 16 KB on authenticated requests, causing HAProxy to
#     return 400 to the browser.
#
#   tune.http.maxhdr 256
#     HAProxy's default cap on headers per HTTP message is 101. Keycloak
#     and Nextcloud federation responses routinely carry >100 response
#     headers (Set-Cookie, X-Frame-Options, CSP, CORS, etc.), so requests
#     are rejected with 400 without this increase.
#
# Architecture — Deployment + Hetzner Load Balancer:
#   haproxy-ingress runs as a Deployment (2 replicas) on the agent nodes.
#   A Service of type LoadBalancer is created; the Hetzner cloud controller
#   manager (CCM) wires it to the pre-provisioned LB (cluster module) and
#   manages LB targets and port forwarding automatically. Traffic path:
#
#     Internet → Hetzner LB public IP → haproxy pod (via private network)
#       → Kubernetes Service ClusterIP → application pod
# ═════════════════════════════════════════════════════════════════════════════

resource "helm_release" "haproxy_ingress" {
  name             = "haproxy-ingress"
  repository       = "https://haproxy-ingress.github.io/charts"
  chart            = "haproxy-ingress"
  version          = "0.16.1"
  namespace        = "haproxy-ingress"
  create_namespace = true

  wait    = true
  timeout = 300

  values = [
    <<-YAML
      controller:
        kind: Deployment
        replicaCount: 2

        # Register haproxy as the cluster-wide default IngressClass.
        # openDesk Ingress objects do not set an ingressClassName annotation;
        # they rely on there being exactly one default class.
        ingressClass: haproxy
        ingressClassResource:
          enabled: true
          default: true

        service:
          type: LoadBalancer
          annotations:
            # Use the pre-provisioned LB from the cluster module instead of
            # letting CCM create a new one. This gives a stable IP that the
            # Cloudflare A records already point at.
            load-balancer.hetzner.cloud/id: "${var.lb_id}"
            # Route LB→node traffic via the cluster private network.
            # Prevents NodePort traffic from traversing the public NIC and
            # avoids the need for port 80/443 rules in the node firewall.
            load-balancer.hetzner.cloud/use-private-ip: "true"

        config:
          # global-config-snippet injects raw HAProxy directives into the
          # "global" section of haproxy.cfg, which is the only place these
          # tune.* knobs are accepted.
          global-config-snippet: |
            tune.bufsize 65536
            tune.http.maxhdr 256
    YAML
  ]
}
