terraform {
  required_version = ">= 1.12.5"

  backend "local" {
    path = ".terraform.tfstate"
  }

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.3.0"
    }
  }
}

locals {
  kubeconfig  = "${path.module}/../opentofu-kind/.kubeconfig"
  release     = "kube-prometheus"
  namespace   = "monitoring"
  chart       = "kube-prometheus-stack"
  chart_repo  = "https://prometheus-community.github.io/helm-charts"
  chart_version = "69.8.2"
}

resource "null_resource" "monitoring" {
  triggers = {
    values         = filemd5("${path.module}/values.yaml")
    chart_version  = local.chart_version
    kubeconfig     = local.kubeconfig
    release        = local.release
    namespace      = local.namespace
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      test -f "${local.kubeconfig}" || { echo "Kubeconfig not found. Run tofu apply in opentofu-kind first."; exit 1; }
      command -v helm >/dev/null || { echo "helm not found. Install with: brew install helm"; exit 1; }

      helm repo add prometheus-community "${local.chart_repo}" 2>/dev/null || true
      helm repo update prometheus-community

      helm upgrade --install "${local.release}" prometheus-community/${local.chart} \
        --kubeconfig="${local.kubeconfig}" \
        --namespace "${local.namespace}" \
        --create-namespace \
        --version "${local.chart_version}" \
        --values "${path.module}/values.yaml" \
        --wait \
        --timeout 10m

      kubectl --kubeconfig="${local.kubeconfig}" wait --for=condition=ready pod \
        -l app.kubernetes.io/name=prometheus \
        -n "${local.namespace}" \
        --timeout=600s
      kubectl --kubeconfig="${local.kubeconfig}" wait --for=condition=ready pod \
        -l app.kubernetes.io/name=grafana \
        -n "${local.namespace}" \
        --timeout=300s

      PF_PID=""
      trap 'if [ -n "$PF_PID" ]; then kill "$PF_PID" 2>/dev/null || true; fi' EXIT
      grafana_ready=false
      for i in $(seq 1 30); do
        kubectl --kubeconfig="${local.kubeconfig}" port-forward -n "${local.namespace}" \
          svc/${local.release}-grafana 3000:80 >/tmp/grafana-pf.log 2>&1 &
        PF_PID=$!
        for j in $(seq 1 10); do
          if curl -sf http://127.0.0.1:3000/login >/dev/null; then
            echo "grafana ready"
            grafana_ready=true
            break 2
          fi
          kill -0 "$PF_PID" 2>/dev/null || break
          sleep 1
        done
        kill "$PF_PID" 2>/dev/null || true
        wait "$PF_PID" 2>/dev/null || true
        PF_PID=""
        sleep 1
      done
      if [ "$grafana_ready" != true ]; then
        echo "Grafana did not become ready"
        exit 1
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      helm uninstall "${self.triggers.release}" \
        --kubeconfig="${self.triggers.kubeconfig}" \
        --namespace "${self.triggers.namespace}" \
        2>/dev/null || true
      kubectl --kubeconfig="${self.triggers.kubeconfig}" delete namespace "${self.triggers.namespace}" \
        --ignore-not-found --wait=false
    EOT
  }
}
