# ═════════════════════════════════════════════════════════════════════════════
# cert-manager configuration
#
# cert-manager itself is installed by kube-hetzner's kustomization step via
# a k3s HelmChart CRD (version: "*", latest stable). This module only
# configures the DNS-01 ClusterIssuer and the Cloudflare API token Secret
# that cert-manager needs to complete ACME challenges.
#
# cert-manager manages TLS certificates for all openDesk sub-services.
# openDesk uses a single wildcard certificate (*.od.heinle.cc) issued by
# Let's Encrypt. Wildcards REQUIRE DNS-01 challenge; HTTP-01 cannot issue
# wildcard certificates. We use Cloudflare as the DNS-01 provider.
# ═════════════════════════════════════════════════════════════════════════════

# ── Cloudflare API token secret ───────────────────────────────────────────────
# cert-manager reads this Secret when it needs to complete a DNS-01 challenge:
# it creates a temporary _acme-challenge TXT record in Cloudflare, waits for
# propagation, and then deletes it after Let's Encrypt validates the challenge.
#
# The token needs ONLY Zone.DNS:Edit on heinle.cc — do not use a global token.
resource "kubernetes_secret_v1" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = "cert-manager"
  }

  # kubernetes_secret_v1 base64-encodes values automatically.
  data = {
    api-token = var.cloudflare_api_token
  }
}

# ── ClusterIssuer: letsencrypt-dns ────────────────────────────────────────────
# The name "letsencrypt-dns" is the EXACT name that openDesk's Helmfile
# expects in its Certificate resource manifests. Renaming it will cause
# openDesk's cert-manager integration to fail silently — certificates will
# never be issued because no matching ClusterIssuer can be found.
#
# We use kubectl_manifest (alekc/kubectl provider) rather than
# kubernetes_manifest (hashicorp/kubernetes) because kubernetes_manifest
# validates the manifest against the CRD schema at plan time. When this
# configuration is first applied, cert-manager may not yet have registered its
# CRDs, causing the plan to fail. kubectl_manifest skips schema validation and
# applies raw YAML, which is safe here because the YAML is authored by us.
resource "kubectl_manifest" "letsencrypt_dns_issuer" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-dns
    spec:
      acme:
        # Let's Encrypt production endpoint — issues publicly trusted certs.
        # Use https://acme-staging-v02.api.letsencrypt.org/directory during
        # initial testing to avoid rate limits.
        server: https://acme-v02.api.letsencrypt.org/directory
        email: ${var.letsencrypt_email}
        privateKeySecretRef:
          name: letsencrypt-dns-account-key
        solvers:
          - dns01:
              cloudflare:
                apiTokenSecretRef:
                  name: cloudflare-api-token
                  key: api-token
  YAML

  depends_on = [
    kubernetes_secret_v1.cloudflare_api_token,
  ]
}
