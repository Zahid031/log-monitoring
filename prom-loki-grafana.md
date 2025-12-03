# Monitoring Stack Setup Documentation

This document contains the configuration files for setting up a complete monitoring stack with Grafana, Loki, Prometheus, and Alloy.

## Overview

This setup includes:
- **Grafana Alloy**: Collects logs and metrics
- **Loki**: Stores and queries logs
- **Prometheus**: Stores and queries metrics
- **Grafana**: Visualization dashboard

## Configuration Files

### 1. Loki Configuration

File: `loki-config.yaml`

```yaml
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /tmp/loki
  storage:
    filesystem:
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
```

### 2. Prometheus Configuration

File: `prometheus.yml`

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
```

### 3. Grafana Alloy Configuration

File: `config.alloy`

```alloy
// 1. METRICS COLLECTION (Host System)
// ==========================================

prometheus.exporter.unix "host" {
  rootfs_path = "/rootfs"
  sysfs_path  = "/host/sys"
  procfs_path = "/host/proc"
}

prometheus.scrape "host_scraper" {
  targets    = prometheus.exporter.unix.host.targets
  forward_to = [prometheus.remote_write.default.receiver]
}

prometheus.remote_write "default" {
  endpoint {
    url = "http://prometheus:9090/api/v1/write"
  }
}

// 2. LOGS COLLECTION (Docker Containers)
// ==========================================

// Step A: Find the containers
discovery.docker "linux_containers" {
  host = "unix:///var/run/docker.sock"
}

// Step B: Clean up labels (The Fix)
// We transform the ugly "__meta_docker_container_name" into a clean "container" label
discovery.relabel "container_labels" {
  targets = discovery.docker.linux_containers.targets

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "container"
  }
}

// Step C: Scrape the logs using the RELABELED targets
loki.source.docker "docker_logs" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.relabel.container_labels.output
  forward_to = [loki.write.local.receiver]
}

loki.write "local" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

### 4. Docker Compose Configuration

File: `docker-compose.yml`

```yaml
services:
  # 1. Grafana Alloy (Collector for Logs & Metrics)
  alloy:
    image: grafana/alloy:latest
    container_name: alloy
    volumes:
      - ./config.alloy:/etc/alloy/config.alloy
      # Mount host logs (optional, for accessing /var/log)
      - /var/log:/var/log
      # Mount docker socket for container discovery
      - /var/run/docker.sock:/var/run/docker.sock:ro
      # Mount host filesystem for system metrics
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command: run --server.http.listen-addr=0.0.0.0:12345 --storage.path=/var/lib/alloy/data /etc/alloy/config.alloy
    ports:
      - "12345:12345" # Alloy UI
    networks:
      - monitor-net
    depends_on:
      - loki
      - prometheus

  # 2. Loki (Log Aggregation Store)
  loki:
    image: grafana/loki:3.0.0
    container_name: loki
    volumes:
      - ./loki-config.yaml:/etc/loki/local-config.yaml
    command: -config.file=/etc/loki/local-config.yaml
    ports:
      - "3100:3100"
    networks:
      - monitor-net

  # 3. Prometheus (Metrics Time-Series DB)
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--web.enable-remote-write-receiver' # Allows Alloy to push metrics here
    ports:
      - "9090:9090"
    networks:
      - monitor-net

  # 4. Grafana (Visualization UI)
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin # Change this!
    ports:
      - "3000:3000"
    networks:
      - monitor-net

networks:
  monitor-net:
    driver: bridge
```

## Setup Instructions

### Step 1: Create Directory Structure

```bash
mkdir ~/prometheus-grafana
cd ~/prometheus-grafana
```

### Step 2: Create Configuration Files

Create the following files in the directory:
- `loki-config.yaml`
- `prometheus.yml`
- `config.alloy`
- `docker-compose.yml`

Copy the content from the respective sections above into each file.

### Step 3: Start the Stack

```bash
docker-compose up -d
```

### Step 4: Verify Services

Check if all containers are running:

```bash
docker-compose ps
```

### Step 5: Access the Services

- **Grafana UI**: http://localhost:3000 (username: admin, password: admin)
- **Prometheus UI**: http://localhost:9090
- **Loki API**: http://localhost:3100
- **Alloy UI**: http://localhost:12345

### Step 6: Configure Grafana Data Sources

1. Login to Grafana at http://localhost:3000
2. Add Prometheus data source:
   - URL: `http://prometheus:9090`
3. Add Loki data source:
   - URL: `http://loki:3100`

## What This Setup Does

### Metrics Collection
- Alloy collects host system metrics (CPU, memory, disk, network)
- Metrics are sent to Prometheus
- Prometheus stores the metrics time-series data

### Logs Collection
- Alloy discovers Docker containers automatically
- Container logs are collected and labeled
- Logs are sent to Loki for storage and querying

### Visualization
- Grafana connects to both Prometheus and Loki
- You can create dashboards to visualize metrics and logs together

## Stopping the Stack

```bash
docker-compose down
```

## Troubleshooting

If containers fail to start, check the logs:

```bash
docker-compose logs <service-name>
```

For example:
```bash
docker-compose logs alloy
docker-compose logs loki
```