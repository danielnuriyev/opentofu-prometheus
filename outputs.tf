output "kubeconfig" {
  description = "Path to the Kind cluster kubeconfig (from pulumi-kind)"
  value       = local.kubeconfig
}

output "namespace" {
  description = "Kubernetes namespace for Prometheus and Grafana"
  value       = local.namespace
}

output "grafana_url_local" {
  description = "Grafana URL (via port-forward)"
  value       = "http://localhost:3000"
}

output "prometheus_url_local" {
  description = "Prometheus URL (via port-forward)"
  value       = "http://localhost:9090"
}

output "grafana_credentials" {
  description = "Default Grafana login (change after first login in production)"
  value = {
    username = "admin"
    password = "admin"
  }
  sensitive = true
}

output "verify" {
  description = "Commands to open Grafana and Prometheus"
  value       = <<-EOT
    export KUBECONFIG=${local.kubeconfig}

    kubectl get pods -n ${local.namespace}
    kubectl port-forward -n ${local.namespace} svc/${local.release}-grafana 3000:80
    # open http://localhost:3000 (login: admin / admin)

    kubectl port-forward -n ${local.namespace} svc/${local.release}-prometheus 9090:9090
    # open http://localhost:9090
  EOT
}
