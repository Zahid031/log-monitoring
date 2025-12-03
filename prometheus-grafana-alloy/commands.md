helm upgrade alloy grafana/alloy -f alloy-values.yaml

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack   -n monitoring --create-namespace   -f kps-values.yaml


