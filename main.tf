# ═════════════════════════════════════════════════════════════════════════════
# k3s cluster on Hetzner Cloud
# Module: kube-hetzner/kube-hetzner/hcloud  v2.20.0
# ═════════════════════════════════════════════════════════════════════════════

module "kube_hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "2.20.0"

  hcloud_token = var.hcloud_token

  # The module reads the raw key content (not a path) — file() resolves at plan
  # time, so the keys must exist locally when you run terraform apply.
  ssh_public_key  = file(var.ssh_public_key_path)
  ssh_private_key = file(var.ssh_private_key_path)

  cluster_name = var.cluster_name

  # eu-central is the Hetzner network region that contains nbg1 (Nuremberg),
  # fsn1 (Falkenstein), and hel1 (Helsinki). Required for the module's private
  # network to be created in the correct region.
  network_region = "eu-central"

  # ── Control-plane node pool ────────────────────────────────────────────────
  # Single node: 16 dedicated vCPU / 64 GB RAM (CCX43, x86).
  #
  # openDesk minimum: 12 vCPU / 32 GB RAM. CCX43 gives comfortable headroom
  # for all 35+ openDesk services running on the same node during evaluation.
  #
  # ARM IS NOT SUPPORTED — openDesk ships x86-only container images and Python
  # wheels. Never substitute with CAX (Ampere) instances.
  control_plane_nodepools = [
    {
      name        = "cp-${var.location}"
      server_type = var.node_type # default: ccx43
      location    = var.location  # default: nbg1
      labels      = []
      taints      = []
      count       = 1
    }
  ]

  # No dedicated worker nodes — the single control-plane node runs all workloads.
  agent_nodepools = []

  # Allow regular (non-system) pods to be scheduled on the control-plane node.
  # Mandatory for single-node clusters. The module sets this automatically when
  # there are no agent_nodepools, but we make it explicit for clarity.
  allow_scheduling_on_control_plane = true

  # ── Storage class ─────────────────────────────────────────────────────────
  # Keep enable_local_storage = false (the module default) so the ONLY default
  # StorageClass is hcloud-volumes (Hetzner block storage / CSI driver).
  #
  # WHY: openDesk's OpenProject "seeder" init container writes to a PVC with
  # sticky-bit ownership (setgid directories). local-path uses a simple
  # hostPath bind-mount that doesn't honour sticky-bit semantics across UID
  # boundaries; the seeder job fails with "permission denied" and the pod
  # restarts indefinitely. hcloud-volumes (ext4 formatted block devices) do
  # honour sticky-bit, so the seeder succeeds.
  enable_local_storage = false

  # ── Ingress controller ────────────────────────────────────────────────────
  # "none" = do NOT install the module's built-in ingress controller.
  # We install haproxy-ingress ourselves (haproxy.tf) so we can control the
  # exact tune.bufsize and tune.http.maxhdr values that openDesk requires.
  # The module's built-in haproxy option doesn't expose these parameters.
  ingress_controller = "none"

  # Location for any Hetzner Load Balancer the module might create (e.g. the
  # control-plane API LB). Set to match the node location.
  load_balancer_location = var.location

  # ── Pinned add-on versions ────────────────────────────────────────────────
  # The module fetches the latest release tags from GitHub API at plan time
  # (data.http resources). Pinning avoids GitHub rate-limit errors in CI/CD
  # environments that share an IP and also ensures reproducible deployments.
  # Update these when you want to pick up upstream fixes.
  hetzner_ccm_version = "v1.33.0" # hcloud cloud controller manager
  hetzner_csi_version = "v2.21.2" # hcloud CSI block-storage driver
  kured_version       = "v1.21.0" # Kubernetes reboot daemon

  # ── Firewall rules ────────────────────────────────────────────────────────
  # The haproxy DaemonSet binds to the node's network interface (hostNetwork)
  # on ports 80 and 443. The Hetzner Cloud firewall is applied at the
  # hypervisor level and blocks all ports by default; without these rules all
  # HTTP/S traffic is silently dropped before it reaches haproxy.
  extra_firewall_rules = [
    {
      description     = "Allow inbound HTTP (haproxy hostNetwork)"
      direction       = "in"
      protocol        = "tcp"
      port            = "80"
      source_ips      = ["0.0.0.0/0", "::/0"]
      destination_ips = []
    },
    {
      description     = "Allow inbound HTTPS (haproxy hostNetwork)"
      direction       = "in"
      protocol        = "tcp"
      port            = "443"
      source_ips      = ["0.0.0.0/0", "::/0"]
      destination_ips = []
    },
  ]
}

# ── Kubeconfig file ───────────────────────────────────────────────────────────
# Write the cluster kubeconfig to disk so that kubectl, helmfile, and other
# local tools can use it after `terraform apply` completes.
# File mode 0600 prevents other users on the machine from reading it.
resource "local_sensitive_file" "kubeconfig" {
  content         = module.kube_hetzner.kubeconfig
  filename        = "${path.module}/kubeconfig.yaml"
  file_permission = "0600"
}
