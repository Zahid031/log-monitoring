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
