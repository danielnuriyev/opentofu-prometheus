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
  kubeconfig              = "${path.module}/../pulumi-kind/.kubeconfig"
  release                 = "kube-prometheus"
  namespace               = "monitoring"
  chart                   = "kube-prometheus-stack"
  chart_repo              = "https://prometheus-community.github.io/helm-charts"
  chart_version           = "69.8.2"
  mattermost_webhook_file = "${path.module}/../opentofu-mattermost/mattermost-webhook.url"
  alerting_values_file    = "${path.module}/.generated/grafana-alerting-values.yaml"
  has_mattermost_webhook  = fileexists(local.mattermost_webhook_file)
}

resource "null_resource" "monitoring" {
  triggers = {
    values               = filemd5("${path.module}/values.yaml")
    alerting_template    = fileexists("${path.module}/grafana-alerting-values.yaml.tpl") ? filemd5("${path.module}/grafana-alerting-values.yaml.tpl") : "none"
    mattermost_webhook   = local.has_mattermost_webhook ? filemd5(local.mattermost_webhook_file) : "none"
    chart_version        = local.chart_version
    kubeconfig           = local.kubeconfig
    release              = local.release
    namespace            = local.namespace
    has_mattermost       = tostring(local.has_mattermost_webhook)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      test -f "${local.kubeconfig}" || { echo "Kubeconfig not found. Run pulumi up in pulumi-kind first."; exit 1; }
      command -v helm >/dev/null || { echo "helm not found. Install with: brew install helm"; exit 1; }

      mkdir -p "${path.module}/.generated"
      HELM_VALUES_ARGS=(--values "${path.module}/values.yaml")

      if [ "${local.has_mattermost_webhook}" = "true" ]; then
        MATTERMOST_WEBHOOK_URL="$(tr -d '\r\n' < "${local.mattermost_webhook_file}")"
        sed "s|\$${mattermost_webhook_url}|$MATTERMOST_WEBHOOK_URL|g" \
          "${path.module}/grafana-alerting-values.yaml.tpl" > "${local.alerting_values_file}"
        HELM_VALUES_ARGS+=(--values "${local.alerting_values_file}")

        kubectl --kubeconfig="${local.kubeconfig}" create namespace "${local.namespace}" --dry-run=client -o yaml | kubectl apply -f -
        kubectl --kubeconfig="${local.kubeconfig}" create secret generic mattermost-grafana-webhook \
          -n "${local.namespace}" \
          --from-literal=url="$MATTERMOST_WEBHOOK_URL" \
          --dry-run=client -o yaml | kubectl apply -f -
      fi

      helm repo add prometheus-community "${local.chart_repo}" 2>/dev/null || true
      helm repo update prometheus-community

      helm upgrade --install "${local.release}" prometheus-community/${local.chart} \
        --kubeconfig="${local.kubeconfig}" \
        --namespace "${local.namespace}" \
        --create-namespace \
        --version "${local.chart_version}" \
        "$${HELM_VALUES_ARGS[@]}" \
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
      kubectl --kubeconfig="${self.triggers.kubeconfig}" wait --for=delete namespace/"${self.triggers.namespace}" --timeout=120s 2>/dev/null || true
    EOT
  }
}
