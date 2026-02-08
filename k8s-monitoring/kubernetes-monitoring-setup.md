# Kubernetes Monitoring Stack Setup Guide

Simple guide to deploy Prometheus, Grafana, and Alloy for monitoring and logging in Kubernetes.

## What This Installs

- **Prometheus**: Collects metrics from your cluster
- **Grafana**: Dashboard for visualization
- **Alloy**: Collects logs and sends to Loki
- **Node Exporter**: Exports hardware metrics
- **Kube State Metrics**: Exports Kubernetes metrics
- **Alertmanager**: Manages alerts

## Prerequisites

- Running Kubernetes cluster
- `kubectl` installed and configured
- `helm` version 3.x installed
- Loki running at `http://192.168.169.34:3100` (update if different)

## Installation Steps

### Step 1: Add Helm Repositories

```bash
# Add Prometheus repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

# Add Grafana repository (for Alloy)
helm repo add grafana https://grafana.github.io/helm-charts

# Update repositories
helm repo update
```

### Step 2: Create Namespace

```bash
kubectl create namespace monitoring
```

### Step 3: Install Prometheus Stack

Create `prometheus-values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    retention: 2d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 15Gi

grafana:
  enabled: true
  adminUser: dev-user
  adminPassword: devuser@321
  service:
    type: NodePort
    nodePort: 32000
  persistence:
    enabled: true
    storageClassName: local-path
    size: 5Gi
  initChownData:
    enabled: true
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://192.168.169.34:3100
      access: proxy
      isDefault: false

alertmanager:
  enabled: true
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi

nodeExporter:
  enabled: true

promtail:
  enabled: false

kubeStateMetrics:
  enabled: true
```

Install:
```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f prometheus-values.yaml
```

### Step 4: Install Alloy

Create `alloy-values.yaml`:

```yaml
alloy:
  configMap:
    content: |
      discovery.kubernetes "pods" {
        role = "pod"
      }

      discovery.relabel "kubernetes_pods" {
        targets = discovery.kubernetes.pods.targets

        rule {
          replacement  = "kubernetes-pods"
          target_label = "job"
        }

        // Drop non-running pods
        rule {
          source_labels = ["__meta_kubernetes_pod_phase"]
          regex         = "Pending|Succeeded|Failed|Completed"
          action        = "drop"
        }

        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          target_label  = "namespace"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_name"]
          target_label  = "pod"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          target_label  = "container"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_node_name"]
          target_label  = "node"
        }
      }

      loki.process "pod_logs" {
        stage.cri {}
        forward_to = [loki.write.remote.receiver]
      }

      loki.source.kubernetes "pods" {
        targets    = discovery.relabel.kubernetes_pods.output
        forward_to = [loki.process.pod_logs.receiver]
      }

      loki.write "remote" {
        endpoint {
          url = "http://192.168.169.34:3100/loki/api/v1/push"
        }
      }

controller:
  type: daemonset

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

rbac:
  create: true

serviceAccount:
  create: true
```

Install:
```bash
helm install alloy grafana/alloy \
  -n monitoring \
  -f alloy-values.yaml
```

## Verify Installation

Check all pods are running:

```bash
kubectl get pods -n monitoring
```

You should see:
- `alertmanager-kube-prometheus-kube-prome-alertmanager-0` - Running
- `alloy-xxxxx` (multiple, one per node) - Running  
- `kube-prometheus-grafana-xxxxx` - Running
- `kube-prometheus-kube-prome-operator-xxxxx` - Running
- `kube-prometheus-kube-state-metrics-xxxxx` - Running
- `kube-prometheus-prometheus-node-exporter-xxxxx` (multiple, one per node) - Running
- `prometheus-kube-prometheus-kube-prome-prometheus-0` - Running

## Access Services

### Grafana Dashboard

```bash
# Access via NodePort
http://<any-node-ip>:32000
```

**Login:**
- Username: `dev-user`
- Password: `devuser@321`

**⚠️ Change the password in production!**

### Prometheus (Optional)

```bash
# Port forward to access locally
kubectl port-forward -n monitoring svc/kube-prometheus-kube-prome-prometheus 9090:9090

# Then open browser
http://localhost:9090
```

## Troubleshooting

### Pod in CrashLoopBackOff

```bash
# Check pod logs
kubectl logs -n monitoring <pod-name>

# Describe pod for more details
kubectl describe pod -n monitoring <pod-name>
```

**Common causes:**
- Storage class `local-path` not available
- Insufficient storage space
- Permission issues

### Grafana Not Starting

```bash
# Check if PVC is bound
kubectl get pvc -n monitoring | grep grafana

# Check storage class exists
kubectl get storageclass
```

### Alloy Not Sending Logs

```bash
# Check Loki is reachable
curl http://192.168.169.34:3100/ready

# Check Alloy logs
kubectl logs -n monitoring <alloy-pod-name>
```

### Delete Old Grafana Pod

If you have an old pod stuck in CrashLoopBackOff:

```bash
# Delete the old deployment/pod
kubectl delete pod -n monitoring <old-pod-name>
```

## Useful Commands

```bash
# View all resources
kubectl get all -n monitoring

# Check pod logs
kubectl logs -n monitoring <pod-name>

# Delete old/stuck pods
kubectl delete pod -n monitoring <pod-name>

# Restart a deployment
kubectl rollout restart deployment/<deployment-name> -n monitoring

# Uninstall everything
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall alloy -n monitoring
kubectl delete namespace monitoring
```

## Update Loki URL

If your Loki is at a different URL, update these files:

**In `prometheus-values.yaml`:**
```yaml
grafana:
  additionalDataSources:
    - name: Loki
      url: http://YOUR-LOKI-IP:3100  # Change this
```

**In `alloy-values.yaml`:**
```yaml
loki.write "remote" {
  endpoint {
    url = "http://YOUR-LOKI-IP:3100/loki/api/v1/push"  # Change this
  }
}
```

Then reinstall with updated values files.
