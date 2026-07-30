# Kubernetes monitoring on Kind (OpenTofu)

Deploys [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) for Kind cluster monitoring and app `ServiceMonitor` scraping (e.g. MinIO).

## What it does

- Installs Prometheus, Grafana, Prometheus Operator, node-exporter, and kube-state-metrics in the `monitoring` namespace
- Scrapes cluster metrics and any labeled `ServiceMonitor` resources (e.g. MinIO in `opentofu-minio`)
- Disables Alertmanager and Kind-inaccessible control-plane scrapes (etcd, scheduler, controller-manager)
- Uses reduced CPU/memory limits suitable for a local Kind cluster

## Prerequisites

- [opentofu-kind](https://github.com/danielnuriyev/opentofu-kind) — Kind cluster with `./.kubeconfig`
- [Helm](https://helm.sh/): `brew install helm`

Deploy **before** [opentofu-minio](https://github.com/danielnuriyev/opentofu-minio) when using MinIO Prometheus scraping (ServiceMonitor CRD must exist).

## Deploy

```bash
tofu init
tofu apply
```

## Access Grafana

```bash
export KUBECONFIG=../opentofu-kind/.kubeconfig
kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80
```

Open [http://localhost:3000](http://localhost:3000) — login `admin` / `admin`.

Useful built-in dashboards:

- **Kubernetes / Compute Resources / Cluster**
- **Kubernetes / Compute Resources / Namespace (Pods)**
- **Node Exporter / Nodes**

## Access Prometheus

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-prometheus 9090:9090
```

Open [http://localhost:9090](http://localhost:9090).

## Cleanup

```bash
tofu destroy
```

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Helm install of kube-prometheus-stack |
| `values.yaml` | Kind-tuned Helm values |
| `outputs.tf` | URLs and verify commands |
