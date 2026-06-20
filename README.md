# openDesk on Hetzner Cloud — Terraform IaC

Terraform/OpenTofu configuration that provisions an ephemeral single-node
Kubernetes cluster on Hetzner Cloud and prepares it as a platform for
evaluating [openDesk](https://zendis.de/opendesk) (the ZenDiS sovereign
workplace suite).

**What Terraform manages:**

| Layer | Tool |
|---|---|
| Hetzner node, network, firewall | `hcloud` provider |
| k3s cluster (k3s-based) | `kube-hetzner/kube-hetzner/hcloud` module v2.20.0 |
| haproxy-ingress (DaemonSet, hostNetwork) | `helm_release` |
| cert-manager + ClusterIssuer `letsencrypt-dns` | `helm_release` + `kubectl_manifest` |
| Cloudflare DNS (`*.od.heinle.cc`, `od.heinle.cc`) | `cloudflare` provider |

**What Terraform does NOT manage:**

openDesk itself is deployed by its own Helmfile in a separate step after
`terraform apply` completes. Wrapping the 35+ openDesk Helm charts in
`helm_release` resources would be unmaintainable.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Terraform ≥ 1.10.1 or OpenTofu ≥ 1.8 | `brew install terraform` or `brew install opentofu` |
| Hetzner Cloud account | API token with Read & Write scope |
| Cloudflare account | Zone `heinle.cc` managed in Cloudflare |
| Cloudflare API token | Scope: `Zone.DNS:Edit` on `heinle.cc` only |
| SSH key pair | Used by the module to bootstrap k3s via cloud-init |
| openDesk Helmfile repo | Cloned separately — not part of this repo |

### Node sizing note

The single control-plane node defaults to **CCX43** (16 dedicated x86 vCPU /
64 GB RAM). This satisfies the openDesk evaluation minimum of 12 vCPU / 32 GB.

**ARM instances (CAX / Ampere) are NOT supported.** openDesk ships x86-only
container images and Python wheels. Using a CAX node will result in
crash-looping pods.

---

## Quick start

### 1 — Clone and configure

```bash
git clone https://github.com/very-emmazing/opendesk.git
cd opendesk

cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars   # fill in tokens, zone ID, email
```

### 2 — Initialise providers and module

```bash
terraform init
```

### 3 — Two-phase apply

Provider configuration for `kubernetes`, `helm`, and `kubectl` is derived from
the module's kubeconfig output, which only exists after the cluster has been
created. A single `terraform apply` on a fresh state therefore needs two phases.

**Phase 1 — create the k3s cluster:**

```bash
terraform apply \
  -target=module.kube_hetzner \
  -target=local_sensitive_file.kubeconfig
```

This takes ~5–10 minutes. The module bootstraps a k3s node via cloud-init,
installs the Hetzner CSI driver, and writes `kubeconfig.yaml` to this
directory.

**Phase 2 — install add-ons and DNS:**

```bash
terraform apply
```

This installs haproxy-ingress, cert-manager, creates the `letsencrypt-dns`
ClusterIssuer, and creates the Cloudflare DNS records. Takes ~3–5 minutes.

After both phases, `terraform output` shows the node IP, kubeconfig path, and
portal URL.

---

## Step 4 — Deploy openDesk

> **This is a manual step — Terraform intentionally stops here.**

```bash
# Export the kubeconfig written by Terraform
export KUBECONFIG="$(terraform output -raw kubeconfig_path)"

# Verify the platform is ready
kubectl get nodes          # should show 1 node, Ready
kubectl get storageclass   # should show hcloud-volumes as (default)
kubectl get ingressclass   # should show haproxy as (default)

# Clone the openDesk Helmfile repository (example; check ZenDiS docs for URL)
git clone https://gitlab.opencode.de/bmi/opendesk/deployment/sovereign-workplace.git
cd sovereign-workplace

# Deploy openDesk
# MASTER_PASSWORD must be set here — it belongs to the openDesk deployment,
# not to Terraform. See the openDesk documentation for all required values.
export MASTER_PASSWORD="<strong-password>"
helmfile apply -e dev -n opendesk
```

The portal will be reachable at **https://portal.od.heinle.cc** once the
Let's Encrypt wildcard certificate has been issued (usually 1–2 minutes after
cert-manager starts).

---

## Teardown — IMPORTANT: read before destroying

**Terraform does not know about Hetzner block volumes created at runtime.**

When openDesk deploys, the Hetzner CSI driver creates block volumes in your
Hetzner project for each PersistentVolumeClaim. These volumes are _not_ in
Terraform state (Terraform never created them — the CSI driver did, in
response to a PVC created by a Helm chart). Running `terraform destroy`
without cleaning them up first will leave orphaned volumes that:

1. Continue to incur hourly charges in your Hetzner account.
2. Cannot be imported into Terraform retroactively.

### Correct teardown order

```bash
# 1. Remove openDesk and its PVCs (waits for volumes to be deleted by CSI)
export KUBECONFIG="$(terraform output -raw kubeconfig_path)"
helmfile destroy -e dev -n opendesk
kubectl delete namespace opendesk --wait=true

# 2. Confirm in the Hetzner console that no leftover volumes remain
#    Console → Cloud → <project> → Volumes
#    If orphaned volumes appear, delete them manually before proceeding.

# 3. Destroy all Terraform-managed resources
terraform destroy
```

---

## Configuration reference

| Variable | Default | Description |
|---|---|---|
| `hcloud_token` | — | Hetzner Cloud API token (sensitive) |
| `cloudflare_api_token` | — | Cloudflare token, Zone.DNS:Edit on heinle.cc (sensitive) |
| `cloudflare_zone_id` | — | Cloudflare Zone ID for heinle.cc |
| `cloudflare_zone_name` | `heinle.cc` | Cloudflare zone root domain |
| `letsencrypt_email` | — | Email for ACME account |
| `ssh_public_key_path` | `~/.ssh/id_ed25519.pub` | SSH public key for node access |
| `ssh_private_key_path` | `~/.ssh/id_ed25519` | SSH private key for cloud-init bootstrap |
| `cluster_name` | `opendesk-eval` | Prefix for Hetzner resource names |
| `node_type` | `ccx43` | Hetzner server type (x86 only, min 12 vCPU/32 GB) |
| `location` | `nbg1` | Hetzner datacenter (Nuremberg) |
| `base_domain` | `od.heinle.cc` | Base domain for openDesk |

---

## Architecture decisions

### Why haproxy-ingress with DaemonSet + hostNetwork?

openDesk's own documentation recommends haproxy-ingress. The DaemonSet with
`hostNetwork: true` binds directly to the node's NIC on ports 80/443,
eliminating the need for a Hetzner Load Balancer (saves ~€12/month on an eval
cluster). DNS points directly at the node IP.

### Why `hcloud-volumes` only (no `local-path`)?

openDesk's OpenProject component runs an init container ("seeder") that writes
to a PVC with sticky-bit ownership semantics. `local-path` uses a simple
`hostPath` bind-mount that doesn't honour cross-UID sticky-bit ownership;
the seeder job crashes with "permission denied". `hcloud-volumes` (ext4 block
devices) correctly handle this.

### Why DNS-01 and not HTTP-01?

Let's Encrypt only issues wildcard certificates (`*.od.heinle.cc`) via DNS-01.
HTTP-01 is limited to exact hostnames.

### Why is `proxied = false` on Cloudflare records?

Two reasons: (1) DNS-01 ACME challenge TXT record lookups must resolve
directly — Cloudflare's proxy intercepts and can mask TXT records. (2)
WebSocket connections used by Collabora Online, Nextcloud Talk, and Element
are broken by Cloudflare's free-tier 100-second proxy timeout.
