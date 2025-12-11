# Kubernetes Logging with Grafana Alloy - Quick Setup

## Prerequisites
- Kubernetes cluster running
- Helm 3 installed
- Loki server running (e.g., `http://192.168.56.6:3100`)

## Setup Steps

### 1. Add Grafana Helm Repository
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### 2. Create Configuration File

Create `alloy-values.yaml`:

```yaml
alloy:
  configMap:
    content: |
      // 1. LOGS COLLECTION (Kubernetes Pods)
      // ==========================================
      // Step A: Discover Kubernetes pods
      discovery.kubernetes "pods" {
        role = "pod"
      }

      // Step B: Relabel to get clean pod information
      discovery.relabel "kubernetes_pods" {
        targets = discovery.kubernetes.pods.targets

        // Keep only running pods
        rule {
          source_labels = ["__meta_kubernetes_pod_phase"]
          regex         = "Pending|Succeeded|Failed|Completed"
          action        = "drop"
        }

        // Add namespace label
        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          target_label  = "namespace"
        }

        // Add pod name label
        rule {
          source_labels = ["__meta_kubernetes_pod_name"]
          target_label  = "pod"
        }

        // Add container name label
        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          target_label  = "container"
        }

        // Add node name label
        rule {
          source_labels = ["__meta_kubernetes_pod_node_name"]
          target_label  = "node"
        }
      }

      // Step C: Scrape pod logs
      loki.source.kubernetes "pods" {
        targets    = discovery.relabel.kubernetes_pods.output
        forward_to = [loki.write.remote.receiver]
      }

      // Step D: Push logs to remote Loki server
      loki.write "remote" {
        endpoint {
          url = "http://192.168.56.6:3100/loki/api/v1/push"
        }
      }

controller:
  type: daemonset

rbac:
  create: true

serviceAccount:
  create: true

# Add service configuration with required ports
service:
  enabled: true
  type: ClusterIP
  ports:
    - name: http-metrics
      port: 12345
      targetPort: 12345
      protocol: TCP
```

**Important**: Change the Loki URL (`http://192.168.56.6:3100`) to your actual Loki server address.

### 3. Install Alloy
```bash
kubectl create namespace monitoring

helm install alloy grafana/alloy \
  --namespace monitoring \
  -f alloy-values.yaml
```

### 4. Verify Installation
```bash
# Check pods are running
kubectl get pods -n monitoring

# Check logs
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy
```

## Query Logs in Grafana

Use these queries in Grafana Explore:

```logql
# All logs
{namespace="default"}

# Specific pod
{pod="my-app-xyz"}

# Filter by text
{namespace="production"} |= "error"
```

## Uninstall
```bash
helm uninstall alloy --namespace monitoring
kubectl delete namespace monitoring
```

## Troubleshooting

**Pods not starting?**
```bash
kubectl describe pods -n monitoring
```

**Connection to Loki failing?**
- Check Loki URL in `alloy-values.yaml`
- Verify Loki is accessible from the cluster
