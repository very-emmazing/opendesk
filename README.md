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

## Current status — ready for `terraform apply`

The code in this repository has been:

- **Written** — all `.tf` files are complete and internally consistent.
- **Formatted** — `terraform fmt` passes with no changes.
- **Validated** — `terraform validate` passes with zero errors and zero warnings.
- **Plan-checked** — a targeted plan against the Hetzner module confirmed 10 resources planned correctly, including the CCX43 server, firewall with TCP 80/443 open, private network, and k3s bootstrap scaffolding.

**Nothing has been applied.** No Hetzner resources exist yet, no DNS records have been written, no Kubernetes cluster is running. You are at the starting line.

---

## What to do next

### Step 0 — Gather your credentials

You need four things before running any Terraform command:

| What | Where to get it |
|---|---|
| Hetzner Cloud API token | Console → Security → API Tokens → Create (Read & Write) |
| Cloudflare API token | Cloudflare dashboard → My Profile → API Tokens → Create Token → `Zone.DNS:Edit` scoped to `heinle.cc` |
| Cloudflare Zone ID | Cloudflare dashboard → select `heinle.cc` → Overview → Zone ID (right sidebar) |
| SSH key pair | Any existing `~/.ssh/id_ed25519` pair, or generate with `ssh-keygen -t ed25519` |

You also need an email address for the Let's Encrypt ACME account.

### Step 1 — Clone and configure

```bash
git clone https://github.com/very-emmazing/opendesk.git
cd opendesk

cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars   # fill in all five required values
```

The variables file is `.gitignore`d — it will not be committed.

### Step 2 — Initialise Terraform

```bash
terraform init
```

This downloads the `kube-hetzner` module (~11 sub-modules) and all providers.
Expect ~1–2 minutes on first run.

### Step 3 — Phase 1: create the cluster

The `kubernetes`, `helm`, and `kubectl` providers read their connection details
from the cluster's kubeconfig, which only exists after the cluster is running.
A two-phase apply is therefore required on a fresh state.

```bash
terraform apply \
  -target=module.kube_hetzner \
  -target=local_sensitive_file.kubeconfig
```

Type `yes` when prompted. This takes **5–10 minutes**: the module creates the
Hetzner server, boots MicroOS, installs k3s, deploys the Hetzner cloud
controller and CSI driver, and writes `kubeconfig.yaml` to this directory.

### Step 4 — Phase 2: install add-ons and DNS

```bash
terraform apply
```

Type `yes` when prompted. This takes **3–5 minutes** and:

- Installs haproxy-ingress as a DaemonSet (hostNetwork, ports 80/443).
- Installs cert-manager with CRDs.
- Creates the `letsencrypt-dns` ClusterIssuer (Cloudflare DNS-01 solver).
- Creates Cloudflare A records for `*.od.heinle.cc` and `od.heinle.cc`.

After this phase completes, check what Terraform outputs:

```bash
terraform output
```

You should see the node IP, the local kubeconfig path, and the portal URL.

### Step 5 — Verify the platform

```bash
export KUBECONFIG="$(terraform output -raw kubeconfig_path)"

kubectl get nodes
# Expected: 1 node, STATUS=Ready

kubectl get storageclass
# Expected: hcloud-volumes (default)  — local-path should NOT appear

kubectl get ingressclass
# Expected: haproxy (default)

kubectl -n cert-manager get clusterissuer letsencrypt-dns
# Expected: READY=True  (may take 30–60 s for ACME registration)
```

If anything is not Ready, check `kubectl -n <namespace> get pods` for the
relevant component before proceeding.

### Step 6 — Deploy openDesk

> **This is a manual step — Terraform intentionally stops here.**
> openDesk ships as a Helmfile orchestrating 35+ Helm charts with its own
> environment layering; Terraform does not touch it.

```bash
# Clone the openDesk deployment repository
# (Verify the canonical URL in the ZenDiS / openCode documentation)
git clone https://gitlab.opencode.de/bmi/opendesk/deployment/sovereign-workplace.git
cd sovereign-workplace

# MASTER_PASSWORD is the bootstrap password for all openDesk services.
# Set it here — it belongs to the Helmfile step, not to Terraform.
export MASTER_PASSWORD="<choose-a-strong-password>"
export KUBECONFIG="/path/to/opendesk/kubeconfig.yaml"  # from terraform output

helmfile apply -e dev -n opendesk
```

The portal will be reachable at **https://portal.od.heinle.cc** once the
Let's Encrypt wildcard certificate has been issued (usually 1–2 minutes after
cert-manager starts the DNS-01 challenge).

---

## Teardown — IMPORTANT: read before destroying

**Terraform does not know about Hetzner block volumes created at runtime.**

When openDesk deploys, the Hetzner CSI driver creates block volumes in your
Hetzner project for each PersistentVolumeClaim. These volumes are _not_ in
Terraform state (Terraform never created them — the CSI driver did, in
response to PVCs created by Helm charts). Running `terraform destroy` without
cleaning them up first will leave orphaned volumes that:

1. Continue to incur hourly charges in your Hetzner account.
2. Cannot be imported into Terraform retroactively.

### Correct teardown order

```bash
export KUBECONFIG="$(terraform output -raw kubeconfig_path)"

# 1. Uninstall openDesk and delete its PVCs.
#    The CSI driver will delete the backing Hetzner volumes as PVCs are removed.
helmfile destroy -e dev -n opendesk
kubectl delete namespace opendesk --wait=true

# 2. Confirm in the Hetzner console that no leftover volumes remain.
#    Console → Cloud → <your project> → Volumes
#    If any orphaned volumes appear, delete them manually before continuing.

# 3. Destroy all Terraform-managed resources.
cd /path/to/opendesk  # the Terraform repo root
terraform destroy
```

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
crash-looping pods. The `node_type` variable has a validation rule that
rejects any value starting with `cax`.

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
