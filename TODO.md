# TODO — Prod Readiness Checklist

Items to address before scaling beyond the dev cluster.

---

## Cluster Autoscaling

EKS node group has `max_size = 4` but nothing to actually trigger scale-out.
The native EKS managed node group scaling only handles node replacement, not
scale-out based on pending pods. If you deploy workloads that exceed the
2-node capacity, pods will stay `Pending` indefinitely.

**Options (pick one):**
- **Karpenter** (Recommended) — faster, right-sizes nodes automatically, supports spot
- **Cluster Autoscaler** — simpler, watches for pending pods and scales node groups

---

## External DNS

Deploy [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) to
automatically manage Route 53 DNS records from Kubernetes Ingress/Service
annotations. Without this, every new service requires manual DNS setup.

---

## Secrets Management

Do **not** put secrets in Kubernetes Secret objects as base64. Use one of:

- **External Secrets Operator** — syncs from AWS Secrets Manager to K8s
  Secrets. Supports rotation, templating, and multi-store backends.
- **AWS Secrets Store CSI Driver** — mounts secrets as files in pods.
  Tighter AWS integration, but less flexible than External Secrets Operator.

Either approach removes plaintext secrets from your CI pipeline and git
history, and enables automatic rotation via AWS Secrets Manager.

---

## Monitoring Stack

**Prometheus + Grafana** (via `kube-prometheus-stack` Helm chart).
Non-negotiable even in dev — you need to see what your microservices are
doing: request latency, error rates, pod resource usage, node pressure.

Includes:
- Prometheus (metrics collection + alerting rules)
- Grafana (dashboards)
- Alertmanager (alert routing to Slack/PagerDuty)
- Node Exporter + kube-state-metrics (cluster-level metrics)
