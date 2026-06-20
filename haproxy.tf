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
# DaemonSet + hostNetwork architecture:
#   The pod binds directly to the node's NIC on ports 80/443, so DNS can
#   point straight at the node's public IP. No Hetzner Load Balancer is
#   required, which reduces cost and removes one network hop.
# ═════════════════════════════════════════════════════════════════════════════

resource "helm_release" "haproxy_ingress" {
  name             = "haproxy-ingress"
  repository       = "https://haproxy-ingress.github.io/charts"
  chart            = "haproxy-ingress"
  version          = "0.16.1"
  namespace        = "haproxy-ingress"
  create_namespace = true

  # Wait for rollout to confirm the DaemonSet is healthy before Terraform
  # considers the release successful.
  wait    = true
  timeout = 300

  values = [
    <<-YAML
      controller:
        kind: DaemonSet
        hostNetwork: true

        # Without this toleration the DaemonSet pod cannot be scheduled on the
        # control-plane node (which carries the node-role.kubernetes.io/control-plane
        # taint). On a single-node cluster where there are no agent nodes, this
        # is the only node available.
        tolerations:
          - operator: Exists

        # Register haproxy as the cluster-wide default IngressClass. openDesk's
        # Ingress objects do not specify an ingressClassName annotation; they rely
        # on there being exactly one default class. If no default class is set
        # the ingresses are silently ignored.
        ingressClass: haproxy
        ingressClassResource:
          enabled: true
          default: true

        config:
          # global-config-snippet injects raw HAProxy directives into the
          # "global" section of haproxy.cfg, which is the only place these
          # tune.* knobs are accepted.
          global-config-snippet: |
            tune.bufsize 65536
            tune.http.maxhdr 256
    YAML
  ]

  # Ensure the cluster exists before attempting to install any Helm chart.
  depends_on = [module.kube_hetzner]
}
