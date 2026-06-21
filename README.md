# openDesk on Hetzner Cloud — OpenTofu + Terragrunt IaC

Infrastructure-as-Code that provisions an ephemeral multi-node Kubernetes
cluster on Hetzner Cloud and prepares it as a platform for evaluating
[openDesk](https://zendis.de/opendesk) (the ZenDiS sovereign workplace suite).

The stack is built with **OpenTofu** (not Terraform), orchestrated by
**Terragrunt**, with the whole toolchain pinned via **mise**.

**What the IaC manages:**

| Layer | Where |
|---|---|
| Hetzner nodes, network, firewall | `modules/cluster` (`hcloud` provider) |
| k3s cluster | `modules/cluster` → `kube-hetzner/kube-hetzner/hcloud` v2.20.0 |
| Hetzner Load Balancer (ingress) | `modules/cluster` (`hcloud_load_balancer`) |
| haproxy-ingress (Deployment, LB Service) | `modules/platform` (`helm_release`) |
| cert-manager + ClusterIssuer `letsencrypt-dns` | `modules/platform` (`helm_release` + `kubectl_manifest`) |
| Cloudflare DNS (`*.od.heinle.cc`, `od.heinle.cc`) | `modules/platform` (`cloudflare` provider) |

**What it does NOT manage:**

openDesk itself is deployed by its own Helmfile in a separate step after the
infrastructure is up. Wrapping the 35+ openDesk Helm charts in `helm_release`
resources would be unmaintainable.

---

## Repository layout

```
.
├── .mise.toml                  # pinned toolchain: opentofu, terragrunt, kubectl, helm, helmfile
├── .env.example                # template for TF_VAR_* secrets/account values (copy to .env)
├── terragrunt.hcl              # root Terragrunt config: tofu binary, state backend, common inputs
├── modules/
│   ├── cluster/                # Hetzner nodes + network + Load Balancer + kubeconfig
│   └── platform/               # haproxy-ingress + cert-manager + Cloudflare DNS
└── live/
    ├── cluster/terragrunt.hcl  # cluster unit
    └── platform/terragrunt.hcl # platform unit (depends on cluster)
```

### Why two units instead of one?

The Kubernetes / Helm / kubectl providers need a **live cluster API** to
configure themselves — which doesn't exist until the cluster module has run.
In a single state this forces the awkward two-phase
`tofu apply -target=… ` then `tofu apply` workaround.

Splitting into a `cluster` unit and a `platform` unit, with the platform unit
declaring a Terragrunt `dependency "cluster"`, removes that entirely:
`terragrunt run-all apply` builds the cluster first, then feeds its outputs
(API endpoint + credentials, Load Balancer ID/IP) straight into the platform
unit's providers. **This dependency-ordering is exactly where Terragrunt earns
its place** — a single unit would gain nothing from it.

---

## Step 0 — Install the toolchain with mise

All tools are pinned in [`.mise.toml`](./.mise.toml). Install
[mise](https://mise.jdx.dev) once, then let it provision everything:

```bash
# Install mise (see https://mise.jdx.dev/getting-started.html for other methods)
curl https://mise.run | sh

cd opendesk
mise trust          # approve this repo's .mise.toml
mise install        # installs opentofu, terragrunt, kubectl, helm, helmfile

mise exec -- tofu version
mise exec -- terragrunt --version
```

Either prefix commands with `mise exec --`, or run `mise activate` in your
shell so the pinned binaries are on `PATH` automatically. The rest of this
README assumes the tools are active (plain `terragrunt`, `tofu`, `kubectl`).

> Versions in `.mise.toml` are pinned at the minor level (e.g. `opentofu =
> "1.8"`); mise resolves the latest matching patch. Bump them deliberately.

## Step 1 — Provide credentials

Secrets and account-specific values are supplied as `TF_VAR_*` environment
variables — **nothing secret is ever written to a committed file**.

```bash
cp .env.example .env
$EDITOR .env                 # fill in the four required values
set -a; source .env; set +a  # export them into the shell
```

`.env` is `.gitignored`. Required values:

| Variable | Where to get it |
|---|---|
| `TF_VAR_hcloud_token` | Hetzner Console → Security → API Tokens → Create (Read & Write) |
| `TF_VAR_cloudflare_api_token` | Cloudflare → My Profile → API Tokens → `Zone.DNS:Edit` scoped to `heinle.cc` |
| `TF_VAR_cloudflare_zone_id` | Cloudflare → select `heinle.cc` → Overview → Zone ID |
| `TF_VAR_letsencrypt_email` | Any email for the ACME account |

You also need an SSH key pair (defaults to `~/.ssh/id_ed25519[.pub]`; override
with `TF_VAR_ssh_public_key_path` / `TF_VAR_ssh_private_key_path`).

Non-secret tunables (cluster name, location, node sizes, LB type, base domain)
live centrally in [`terragrunt.hcl`](./terragrunt.hcl) — edit them there.

## Step 2 — Apply the whole stack

Terragrunt resolves the `cluster → platform` dependency and applies them in
order, with a single command:

```bash
terragrunt run-all apply
```

Review the plans, type `yes` when prompted (or add
`--terragrunt-non-interactive` once you trust it). This takes **~10–15 minutes**
total:

1. **cluster** (~5–10 min) — creates the Hetzner servers, boots MicroOS,
   installs k3s + Hetzner CCM/CSI, provisions the Load Balancer, and writes
   `kubeconfig.yaml` to the repo root.
2. **platform** (~3–5 min) — installs haproxy-ingress (LoadBalancer Service
   bound to the LB), cert-manager + the `letsencrypt-dns` ClusterIssuer, and
   the Cloudflare A records for `*.od.heinle.cc` / `od.heinle.cc`.

To work on a single unit, `cd` into it and use plain Terragrunt:

```bash
cd live/cluster   && terragrunt apply
cd live/platform  && terragrunt apply
```

> Planning the **platform** unit before the cluster exists requires the cluster
> to be applied first (its providers need a live API). `run-all apply` handles
> this ordering for you. For a from-scratch dry run, apply `cluster` first,
> then `terragrunt plan` the platform unit.

## Step 3 — Verify the platform

```bash
export KUBECONFIG="$(pwd)/kubeconfig.yaml"   # written by the cluster unit

kubectl get nodes
# Expected: 4 nodes (1 control-plane + 3 agents), STATUS=Ready

kubectl get storageclass
# Expected: hcloud-volumes (default)  — local-path should NOT appear

kubectl get ingressclass
# Expected: haproxy (default)

kubectl -n cert-manager get clusterissuer letsencrypt-dns
# Expected: READY=True  (may take 30–60 s for ACME registration)

kubectl -n haproxy-ingress get svc
# Expected: haproxy-ingress  TYPE=LoadBalancer  with the Hetzner LB EXTERNAL-IP
```

## Step 4 — Deploy openDesk

> **This is a manual step — the IaC intentionally stops here.**
> openDesk ships as a Helmfile orchestrating 35+ Helm charts with its own
> environment layering; the IaC does not touch it.

```bash
# Clone the openDesk deployment repository
# (Verify the canonical URL in the ZenDiS / openCode documentation)
git clone https://gitlab.opencode.de/bmi/opendesk/deployment/sovereign-workplace.git
cd sovereign-workplace

# MASTER_PASSWORD is the bootstrap password for all openDesk services.
# It belongs to the Helmfile step, not to the IaC.
export MASTER_PASSWORD="<choose-a-strong-password>"
export KUBECONFIG="/path/to/opendesk/kubeconfig.yaml"

helmfile apply -e dev -n opendesk
```

The portal will be reachable at **https://portal.od.heinle.cc** once the
Let's Encrypt wildcard certificate has been issued (usually 1–2 minutes after
cert-manager starts the DNS-01 challenge).

---

## Step 5 — Post-portal configuration

Everything below happens **after** `https://portal.od.heinle.cc` loads in the
browser. Nothing here requires touching the IaC.

### 5.1 Retrieve the auto-generated admin password

openDesk generates credentials on first deploy and stores them in a Kubernetes
secret:

```bash
export KUBECONFIG="/path/to/opendesk/kubeconfig.yaml"

kubectl -n opendesk get secret ums-nubus-credentials \
  -o jsonpath='{.data.administrator_password}' | base64 -d
```

Log in with username `Administrator` and that password. **Change it immediately**
after first login.

### 5.2 Verify the wildcard certificate issued

cert-manager runs the Let's Encrypt DNS-01 challenge in the background. Confirm
it completed before trusting any service:

```bash
kubectl -n cert-manager get clusterissuer letsencrypt-dns
# READY=True required

kubectl -n opendesk get certificate
# All certificates should show READY=True
```

If a certificate is stuck, inspect
`kubectl -n opendesk describe certificate <name>` for the ACME challenge status.

### 5.3 Create users

openDesk has no self-registration. The admin must create accounts manually.
Three options in order of effort:

| Method | When to use |
|---|---|
| Portal UI → Administrator → Users → Create | A handful of test accounts |
| openDesk User Importer script (UDM REST API) | Bulk import from a CSV |
| LDAP/UCS federation via Keycloak | Existing corporate directory |

For an eval, create at least one non-admin test user and confirm the end-user
login flow works.

### 5.4 Change OpenProject's default password

OpenProject ships with its own local admin account (`admin` / `admin`)
independent of the central SSO. Log in via the portal → OpenProject tile, then
go to **Avatar → Administration** and change the password before anyone else
reaches it.

### 5.5 Configure SMTP

openDesk includes Postfix, but without a smarthost it cannot deliver email
externally. Without this, password-reset emails, OpenProject notifications, and
calendar invites are silently queued. Edit
`helmfile/environments/default/functional.yaml.gotmpl` in your openDesk repo:

```yaml
smtp:
  host: "your-smarthost.example.com"
  username: "user"
  password: "secret"
```

Then reapply: `helmfile apply -e dev -n opendesk`.

### 5.6 Configure a TURN server for video calls

Element (chat) and Jitsi (video) both require a TURN/STUN server to establish
peer-to-peer connections through NAT. Without it, video calls fail for most
users. This is the single most common reason calls don't work on a fresh
install. Add TURN details to your helmfile functional values:

```yaml
functional:
  element:
    turnServer:
      host: "turn.your-domain.example.com"
      port: 3478
      secret: "your-turn-secret"
```

You can run [coturn](https://github.com/coturn/coturn) on any small VM, or use
a hosted TURN service, then reapply helmfile.

### 5.7 Verify core functionality (smoke test)

```bash
kubectl -n opendesk get pods
# All pods should be Running or Completed — allow 5–10 min for init containers
# (database migrations, OpenProject seeder, etc.) to finish first
```

Then run through this checklist before declaring the environment ready:

- [ ] Admin login at `https://portal.od.heinle.cc`
- [ ] Test-user login — SSO flows to each tile without a second password prompt
- [ ] Nextcloud: file upload and download
- [ ] Element: send a chat message
- [ ] OpenProject: create a project and a task
- [ ] Jitsi: start a meeting (audio/video only reliable once TURN is configured)
- [ ] Email: trigger a password-reset for the test user and confirm delivery

### 5.8 Optional / production-only steps

| Topic | What |
|---|---|
| **External IdP** | Federate Keycloak with Azure AD / Okta via OIDC or SAML. Keycloak admin console: `https://keycloak.od.heinle.cc/admin` (user: `kcadmin`, password in the `ums-keycloak` pod env). |
| **Matrix federation** | Set `functional.matrix.federation.enabled: true` in helmfile values to allow Element users to chat across Matrix servers. |
| **Separate mail domain** | By default addresses are `user@od.heinle.cc`. A dedicated `mail.od.heinle.cc` subdomain can be configured for outbound mail identity. |
| **Monitoring** | openDesk exposes Prometheus metrics. Add a Prometheus + Grafana stack separately; nothing is wired up by default. |
| **Backups** | All state lives in hcloud-volumes PVCs. Set up snapshot schedules in the Hetzner console or deploy Velero before going beyond eval. |

---

## Teardown — IMPORTANT: read before destroying

**The IaC does not know about Hetzner block volumes created at runtime.**

When openDesk deploys, the Hetzner CSI driver creates block volumes in your
Hetzner project for each PersistentVolumeClaim. These volumes are _not_ in
OpenTofu state (the IaC never created them — the CSI driver did, in response to
PVCs created by Helm charts). Destroying the cluster without cleaning them up
first leaves orphaned volumes that:

1. Continue to incur hourly charges in your Hetzner account.
2. Cannot be imported into state retroactively.

### Correct teardown order

```bash
export KUBECONFIG="/path/to/opendesk/kubeconfig.yaml"

# 1. Uninstall openDesk and delete its PVCs.
#    The CSI driver deletes the backing Hetzner volumes as PVCs are removed.
helmfile destroy -e dev -n opendesk
kubectl delete namespace opendesk --wait=true

# 2. Confirm in the Hetzner console that no leftover volumes remain.
#    Console → Cloud → <your project> → Volumes
#    If any orphaned volumes appear, delete them manually before continuing.

# 3. Destroy the IaC — platform first, then cluster (reverse dependency order).
terragrunt run-all destroy
```

`run-all destroy` tears the units down in reverse dependency order
(platform → cluster). To do it by hand: `cd live/platform && terragrunt
destroy`, then `cd live/cluster && terragrunt destroy`.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| mise | Provisions the pinned toolchain (`mise install`) |
| OpenTofu ≥ 1.8 | Installed by mise; driven by Terragrunt (`terraform_binary = "tofu"`) |
| Terragrunt ~ 0.67 | Installed by mise; orchestrates the units |
| Hetzner Cloud account | API token with Read & Write scope |
| Cloudflare account | Zone `heinle.cc` managed in Cloudflare |
| Cloudflare API token | Scope: `Zone.DNS:Edit` on `heinle.cc` only |
| SSH key pair | Used by the module to bootstrap k3s via cloud-init |
| openDesk Helmfile repo | Cloned separately — not part of this repo |

### Node sizing note

The cluster uses a split control-plane / worker topology:

| Role | Default type | vCPU | RAM | Count |
|---|---|---|---|---|
| Control-plane | `cx22` | 2 | 4 GB | 1 |
| Agent (worker) | `cx33` | 8 | 16 GB | 3 (default) |
| **Total worker capacity** | | **24** | **48 GB** | |

The openDesk evaluation minimum is 12 vCPU / 32 GB. Three `cx33` agents
provide 24 vCPU / 48 GB — roughly 2× the minimum, with comfortable headroom for
all 35+ openDesk services. The control-plane node runs only k3s system
components and does not contribute to workload capacity.

Adjust `agent_count` or `agent_type` in [`terragrunt.hcl`](./terragrunt.hcl) if
you need more or less capacity. The maximum per-node type is `cx33`
(8 vCPU / 16 GB).

**ARM instances (CAX / Ampere) are NOT supported.** openDesk ships x86-only
container images and Python wheels. Using a CAX node will result in
crash-looping pods. Both `control_plane_type` and `agent_type` have validation
rules that reject any value starting with `cax`.

---

## Configuration reference

Common, non-secret tunables are set in [`terragrunt.hcl`](./terragrunt.hcl);
secrets and account-specific values are passed as `TF_VAR_*` env vars (see
[`.env.example`](./.env.example)).

| Setting | Source | Default | Description |
|---|---|---|---|
| `TF_VAR_hcloud_token` | env | — | Hetzner Cloud API token (secret) |
| `TF_VAR_cloudflare_api_token` | env | — | Cloudflare token, Zone.DNS:Edit on heinle.cc (secret) |
| `TF_VAR_cloudflare_zone_id` | env | — | Cloudflare Zone ID for heinle.cc |
| `TF_VAR_letsencrypt_email` | env | — | Email for the ACME account |
| `ssh_public_key_path` | env (optional) | `~/.ssh/id_ed25519.pub` | SSH public key for node access |
| `ssh_private_key_path` | env (optional) | `~/.ssh/id_ed25519` | SSH private key for cloud-init bootstrap |
| `cluster_name` | terragrunt.hcl | `opendesk-eval` | Prefix for Hetzner resource names |
| `control_plane_type` | terragrunt.hcl | `cx22` | Control-plane server type (x86 only) |
| `agent_type` | terragrunt.hcl | `cx33` | Worker server type (x86 only, max cx33) |
| `agent_count` | terragrunt.hcl | `3` | Number of worker nodes |
| `lb_type` | terragrunt.hcl | `lb11` | Hetzner Load Balancer type for ingress |
| `location` | terragrunt.hcl | `nbg1` | Hetzner datacenter (Nuremberg) |
| `base_domain` | terragrunt.hcl | `od.heinle.cc` | Base domain for openDesk |
| `cloudflare_zone_name` | terragrunt.hcl | `heinle.cc` | Cloudflare zone root domain |

---

## Architecture decisions

### Why OpenTofu and not Terraform?

OpenTofu is the open-source, community-governed fork of Terraform under the
Linux Foundation, MPL-licensed without the BUSL restrictions. The configuration
is otherwise compatible; Terragrunt is told to invoke the `tofu` binary via
`terraform_binary = "tofu"` in [`terragrunt.hcl`](./terragrunt.hcl).

### Why Terragrunt (and only here)?

Terragrunt is used for exactly one reason: to split the stack into a `cluster`
unit and a `platform` unit and order them via a `dependency` block, so the
Kubernetes/Helm providers always see a live API. It also keeps the state
backend and common inputs DRY across units. It is **not** used to wrap a single
monolithic module — that would add indirection without benefit.

### Why mise for tooling?

Pinning OpenTofu, Terragrunt, kubectl, helm and helmfile in `.mise.toml` gives
every contributor and CI runner byte-identical tool versions with a single
`mise install`, instead of "works on my machine" version drift.

### Why haproxy-ingress with Deployment + Hetzner Load Balancer?

openDesk's own documentation recommends haproxy-ingress. A Deployment (2
replicas) with `service.type=LoadBalancer` is used instead of a DaemonSet with
`hostNetwork: true`. The Hetzner cloud controller manager (CCM) wires the
Service to a pre-provisioned `hcloud_load_balancer` (in the cluster module) and
manages LB targets and port forwarding automatically.

Benefits over the single-node DaemonSet approach:
- **Stable IP**: the LB IP exists before any node; DNS never needs updating if
  nodes are replaced.
- **No node firewall changes**: the LB routes via the cluster's private network
  (`use-private-ip: "true"`); ports 80/443 do not need to be open on
  individual nodes.
- **High availability**: two haproxy replicas across different worker nodes; LB
  health-checks remove unhealthy targets automatically.

The `lb11` type costs ~€6/month — a reasonable trade-off for the stability
benefits on a multi-node eval cluster.

### Why `hcloud-volumes` only (no `local-path`)?

openDesk's OpenProject component runs an init container ("seeder") that writes
to a PVC with sticky-bit ownership semantics. `local-path` uses a simple
`hostPath` bind-mount that doesn't honour cross-UID sticky-bit ownership; the
seeder job crashes with "permission denied". `hcloud-volumes` (ext4 block
devices) correctly handle this.

### Why DNS-01 and not HTTP-01?

Let's Encrypt only issues wildcard certificates (`*.od.heinle.cc`) via DNS-01.
HTTP-01 is limited to exact hostnames.

### Why is `proxied = false` on Cloudflare records?

Two reasons: (1) DNS-01 ACME challenge TXT record lookups must resolve
directly — Cloudflare's proxy intercepts and can mask TXT records. (2)
WebSocket connections used by Collabora Online, Nextcloud Talk, and Element
are broken by Cloudflare's free-tier 100-second proxy timeout.
