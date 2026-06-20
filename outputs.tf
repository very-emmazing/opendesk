output "node_ipv4" {
  description = "Public IPv4 address of the single control-plane / ingress node. DNS records for *.od.heinle.cc and od.heinle.cc point here."
  value       = module.kube_hetzner.ingress_public_ipv4
}

output "kubeconfig_path" {
  description = "Absolute path to the cluster kubeconfig written by Terraform. Export as KUBECONFIG before running kubectl or helmfile."
  value       = local_sensitive_file.kubeconfig.filename
}

output "portal_url" {
  description = "Expected URL of the openDesk portal once helmfile apply completes. Not reachable until the helmfile step has run."
  value       = "https://portal.${var.base_domain}"
}

output "cluster_name" {
  description = "Name of the Hetzner Cloud cluster (used as prefix for Hetzner resources)."
  value       = module.kube_hetzner.cluster_name
}

output "next_steps" {
  description = "Instructions for the openDesk helmfile deployment step."
  value       = <<-EOT
    ── Terraform complete. Platform is ready. ──

    1. Export the kubeconfig:
         export KUBECONFIG="${local_sensitive_file.kubeconfig.filename}"

    2. Verify the cluster is healthy:
         kubectl get nodes
         kubectl get pods -A

    3. Deploy openDesk (from your openDesk repository):
         helmfile apply -e dev -n opendesk

    Portal will be available at: https://portal.${var.base_domain}

    ── Teardown (read before destroying!) ──
    PVC-backed Hetzner volumes created by the CSI driver at runtime are NOT
    in Terraform state. Destroy them first:
      helmfile destroy -e dev -n opendesk   # or: kubectl delete ns opendesk
      # Then verify no leftover volumes in the Hetzner console before:
      terraform destroy
  EOT
}
