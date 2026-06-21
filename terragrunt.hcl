# ═════════════════════════════════════════════════════════════════════════════
# Root Terragrunt configuration
#
# Inherited by every unit under live/ via `include "root"`. Centralises:
#   - the OpenTofu binary (so `tofu` is used instead of `terraform`)
#   - state backend generation (local backend, persisted outside the cache)
#   - common, non-secret inputs shared across units
#
# Secrets and account-specific values are NOT defined here. They are supplied
# as TF_VAR_* environment variables and flow through automatically:
#   TF_VAR_hcloud_token, TF_VAR_cloudflare_api_token,
#   TF_VAR_cloudflare_zone_id, TF_VAR_letsencrypt_email
# See .env.example.
# ═════════════════════════════════════════════════════════════════════════════

# Drive OpenTofu, not Terraform. Requires `tofu` on PATH (provided by mise).
terraform_binary = "tofu"

# ── State backend ─────────────────────────────────────────────────────────────
# Local backend for an ephemeral eval cluster. Terragrunt runs each unit from a
# copy in .terragrunt-cache, so the state path is pinned to a stable directory
# at the repo root (state/<unit>/terraform.tfstate) rather than inside the cache.
#
# state/ is .gitignored — local state contains plaintext secrets and resource
# IDs and must never be committed.
remote_state {
  backend = "local"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    path = "${get_repo_root()}/state/${path_relative_to_include()}/terraform.tfstate"
  }
}

# ── Common inputs ─────────────────────────────────────────────────────────────
# Shared, non-secret tunables. Edit here to change them once for every unit.
# Units only declare the variables they actually use; OpenTofu silently ignores
# TF_VAR_* values for variables a given module doesn't declare, so it is safe to
# pass the full set to both units.
inputs = {
  cluster_name         = "opendesk-eval"
  location             = "nbg1"
  base_domain          = "od.heinle.cc"
  cloudflare_zone_name = "heinle.cc"

  # Node sizing — x86 only, never CAX/ARM. Max per-node type is cx33.
  control_plane_type = "cx22" # 2 vCPU / 4 GB  — k3s system only
  agent_type         = "cx33" # 8 vCPU / 16 GB — openDesk workloads
  agent_count        = 3      # 3 × cx33 = 24 vCPU / 48 GB total

  # Hetzner Load Balancer for ingress.
  lb_type = "lb11" # 5 Gbit/s, up to 25 targets
}
