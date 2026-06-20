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
  # Single cx22 node (2 vCPU / 4 GB RAM). Runs k3s system components only
  # (API server, scheduler, controller-manager, etcd). All openDesk workloads
  # are scheduled on the agent pool below.
  #
  # ARM IS NOT SUPPORTED — openDesk ships x86-only container images and Python
  # wheels. Never substitute with CAX (Ampere) instances.
  control_plane_nodepools = [
    {
      name        = "cp-${var.location}"
      server_type = var.control_plane_type # default: cx22
      location    = var.location           # default: nbg1
      labels      = []
      taints      = []
      count       = 1
    }
  ]

  # ── Agent (worker) node pool ───────────────────────────────────────────────
  # Three cx33 nodes (8 vCPU / 16 GB RAM each) = 24 vCPU / 48 GB for
  # openDesk workloads. The evaluation minimum is 12 vCPU / 32 GB.
  agent_nodepools = [
    {
      name        = "workers-${var.location}"
      server_type = var.agent_type # default: cx33
      location    = var.location   # default: nbg1
      labels      = []
      taints      = []
      count       = var.agent_count # default: 3
    }
  ]

  # Control-plane is reserved for k3s system components.
  # The module defaults this to false when agent_nodepools is non-empty,
  # but we make it explicit to prevent accidental workload scheduling.
  allow_scheduling_on_control_plane = false

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
