# Kubernetes monitoring on Kind (OpenTofu)

Deploys [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) for Kind cluster monitoring and app `ServiceMonitor` scraping (e.g. MinIO).

## What it does

- Installs Prometheus, Grafana, Prometheus Operator, node-exporter, and kube-state-metrics in the `monitoring` namespace
- Scrapes cluster metrics and any labeled `ServiceMonitor` resources (e.g. MinIO in `opentofu-minio`)
- Disables Alertmanager and Kind-inaccessible control-plane scrapes (etcd, scheduler, controller-manager)
- Uses reduced CPU/memory limits suitable for a local Kind cluster
- Provisions Grafana unified alerting with a **mattermost** contact point (when [opentofu-mattermost](https://github.com/danielnuriyev/opentofu-mattermost) is deployed)

## Prerequisites

- [pulumi-kind](../pulumi-kind/) — Kind cluster with `./.kubeconfig`
- [Helm](https://helm.sh/): `brew install helm`

Deploy **before** [opentofu-minio](https://github.com/danielnuriyev/opentofu-minio) when using MinIO Prometheus scraping (ServiceMonitor CRD must exist).

For Mattermost alert notifications, deploy [opentofu-mattermost](https://github.com/danielnuriyev/opentofu-mattermost) **before** this stack (`mattermost-webhook.url` is required).

## Deploy

```bash
tofu init
tofu apply
```

## Access Grafana

```bash
export KUBECONFIG=../pulumi-kind/.kubeconfig
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

## Grafana alerts to Mattermost

When [opentofu-mattermost](https://github.com/danielnuriyev/opentofu-mattermost) is deployed, `tofu apply` here:

1. Reads the Mattermost incoming webhook URL from `../opentofu-mattermost/mattermost-webhook.url`
2. Provisions a Grafana contact point **mattermost** (Slack-compatible notifier → Mattermost webhook)
3. Sets the default notification policy to deliver Grafana-managed alerts to Mattermost

Alerts land in the Mattermost **Alerts** team → **Grafana Alerts** channel.

### Connect Grafana to Mattermost (manual)

If you use a custom Mattermost webhook:

1. Port-forward Grafana and Mattermost (see READMEs in each project).
2. In Grafana: **Alerting** → **Contact points** → edit **mattermost** (or create new).
3. Type: **Slack** — Mattermost incoming webhooks accept Slack-format payloads.
4. URL: Mattermost incoming webhook (`http://mattermost.mattermost.svc.cluster.local:8065/hooks/…` from inside the cluster).
5. **Test** — confirm the message in Mattermost.

### Send a test alert

**From Grafana UI:** **Alerting** → **Contact points** → **mattermost** → **Test**.

**From the cluster** (uses provisioned contact point URL from Grafana):

```bash
export KUBECONFIG=../pulumi-kind/.kubeconfig

kubectl exec -n monitoring deploy/kube-prometheus-grafana -c grafana -- sh -c '
CP=$(wget -qO- --header="Authorization: Basic YWRtaW46YWRtaW4=" http://localhost:3000/api/v1/provisioning/contact-points)
URL=$(echo "$CP" | grep -o "http://mattermost[^\"]*")
wget -S -O- --header="Content-Type: application/json" --header="Authorization: Basic YWRtaW46YWRtaW4=" \
  --post-data="{\"alert\":{\"annotations\":{\"summary\":\"Test alert\"},\"labels\":{\"alertname\":\"Test\"}},\"receivers\":[{\"name\":\"mattermost\",\"grafana_managed_receiver_configs\":[{\"uid\":\"mattermost\",\"name\":\"mattermost\",\"type\":\"slack\",\"settings\":{\"url\":\"$URL\"}}]}]}" \
  http://localhost:3000/api/alertmanager/grafana/config/api/v1/receivers/test
'
```

Look for `"status":"ok"` in the response.

### Create alert rules that notify Mattermost

The default notification policy routes all Grafana-managed alerts to **mattermost**. New alert rules under **Alerting** → **Alert rules** will notify Mattermost when they fire (no extra contact point wiring needed).

## Cleanup

```bash
tofu destroy
```

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Helm install of kube-prometheus-stack |
| `values.yaml` | Kind-tuned Helm values |
| `grafana-alerting-values.yaml.tpl` | Templated Mattermost contact point and policy |
| `outputs.tf` | URLs and verify commands |
