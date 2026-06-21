# ── Hetzner Cloud ─────────────────────────────────────────────────────────────
# The kube-hetzner module inherits this default provider configuration.
provider "hcloud" {
  token = var.hcloud_token
}
