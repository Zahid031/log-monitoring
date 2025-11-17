# Centralized Docker Log Monitoring Setup

## Architecture Overview

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│  Remote Server  │         │  Remote Server  │         │  Remote Server  │
│   (Docker Host) │         │   (Docker Host) │         │   (Docker Host) │
│                 │         │                 │         │                 │
│     Alloy ──────┼─────────┼─────────────────┼─────────┼──────────────►  │
└─────────────────┘         └─────────────────┘         └─────────────────┘
                                                                │
                                                                │ Push Logs
                                                                ▼
                                    ┌───────────────────────────────────────┐
                                    │      Central Monitoring Server         │
                                    │                                        │
                                    │   Loki (Port 3100) ◄─── Receives logs │
                                    │   Grafana (Port 3000) ─── Visualize   │
                                    └───────────────────────────────────────┘
```

---

## Part 1: Central Monitoring Server Setup

**Server IP Example**: `192.168.1.100`

### Step 1: Create Directory Structure

```bash
mkdir -p /opt/monitoring && cd /opt/monitoring
```

### Step 2: Create Loki Config

Create `loki-config.yaml`:

```yaml
auth_enabled: false

server:
  http_listen_port: 3100
  http_listen_address: 0.0.0.0

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: loki_index_
        period: 24h

storage_config:
  filesystem:
    directory: /loki

limits_config:
  retention_period: 168h
  reject_old_samples: true
  reject_old_samples_max_age: 168h

```

### Step 3: Create Docker Compose

Create `docker-compose.yml`:

```yaml

networks:
  monitoring:
    driver: bridge

services:
  loki:
    image: grafana/loki:3.5
    container_name: loki
    restart: unless-stopped
    user: "10001:10001"
    command: -config.file=/etc/loki/loki-config.yaml
    ports:
      - "3100:3100"
    volumes:
      - ./loki-data:/loki
      - ./loki-config.yaml:/etc/loki/loki-config.yaml:ro
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin123
    volumes:
      - ./grafana-data:/var/lib/grafana
    networks:
      - monitoring
```

### Step 4: Set Permissions and Start

```bash
# Create directories
mkdir -p loki-data grafana-data

# Set permissions
sudo chown -R 10001:10001 loki-data
sudo chown -R 472:472 grafana-data

# Start services
docker-compose up -d

# Check status
docker-compose ps
```

### Step 5: Configure Firewall

```bash
# Allow Loki port (for remote Alloy agents)
sudo ufw allow 3100/tcp

# Allow Grafana port (for web access)
sudo ufw allow 3000/tcp

# Reload firewall
sudo ufw reload
```

### Step 6: Verify Central Server

```bash
# Test Loki
curl http://192.168.1.100:3100/ready

# Access Grafana
# Open browser: http://192.168.1.100:3000
# Login: admin / admin123
```

---

## Part 2: Remote Server Setup (Repeat for Each Docker Host)

**Remote Server IP Example**: `192.168.1.101`, `192.168.1.102`, etc.

### Step 1: Create Alloy Directory

```bash
mkdir -p /opt/alloy && cd /opt/alloy
```

### Step 2: Create Alloy Config

Create `alloy-config.alloy`:

**Important**: Replace `192.168.1.100` with your actual central monitoring server IP.

```hcl
// Discover Docker containers
discovery.docker "containers" {
    host = "unix:///var/run/docker.sock"
}

// Add labels
discovery.relabel "relabel" {
    targets = discovery.docker.containers.targets
    
    rule {
        source_labels = ["__meta_docker_container_name"]
        regex         = "/(.*)"
        target_label  = "container_name"
        replacement   = "$1"
    }
    
    // Add server hostname
    rule {
        target_label = "hostname"
        replacement  = env("HOSTNAME")
    }
}

// Collect logs
loki.source.docker "docker_logs" {
    host          = "unix:///var/run/docker.sock"
    targets       = discovery.relabel.relabel.output
    relabel_rules = discovery.relabel.relabel.rules
    forward_to    = [loki.write.loki_writer.receiver]
}

// Send to central Loki
loki.write "loki_writer" {
    endpoint {
        url = "http://192.168.1.100:3100/loki/api/v1/push"
    }
}
```

### Step 3: Create Docker Compose for Alloy

Create `docker-compose.yml`:

```yaml
version: "3.9"

services:
  alloy:
    image: grafana/alloy:latest
    container_name: alloy
    restart: unless-stopped
    hostname: ${HOSTNAME}
    environment:
      - HOSTNAME=${HOSTNAME}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./alloy-config.alloy:/etc/alloy/config.alloy:ro
      - ./alloy_data:/var/lib/alloy/data
    command:
      - run
      - --server.http.listen-addr=0.0.0.0:12345
      - --storage.path=/var/lib/alloy/data
      - /etc/alloy/config.alloy
    ports:
      - "12345:12345"
```

### Step 4: Start Alloy Agent

```bash
# Create data directory
mkdir -p alloy_data

# Start Alloy
docker-compose up -d

# Check logs
docker-compose logs -f alloy
```

### Step 5: Verify Connection

```bash
# Check Alloy status
curl http://localhost:12345

# Test connection to central Loki
curl http://192.168.1.100:3100/ready
```

---

## Part 3: Configure Grafana

### Add Loki Data Source

1. Open Grafana: `http://192.168.1.100:3000`
2. Login: `admin` / `admin123`
3. Go to: **☰** → **Connections** → **Data Sources**
4. Click **Add data source**
5. Select **Loki**
6. Set URL: `http://loki:3100`
7. Click **Save & Test**

### View Logs

1. Go to: **☰** → **Explore**
2. Select **Loki** data source
3. Try these queries:

```
# All logs from all servers
{container_name=~".+"}

# Logs from specific server
{hostname="server-01"}

# Logs from specific container
{container_name="nginx"}

# Logs from specific container on specific server
{hostname="server-01", container_name="nginx"}

# Filter errors
{container_name="app"} |= "error"
```

---

## Quick Setup Commands

### Central Server (192.168.1.100)
```bash
cd /opt/monitoring
mkdir -p loki-data grafana-data
sudo chown -R 10001:10001 loki-data
sudo chown -R 472:472 grafana-data
sudo ufw allow 3100/tcp
sudo ufw allow 3000/tcp
docker-compose up -d
```

### Remote Servers (192.168.1.101, 102, ...)
```bash
cd /opt/alloy
# Edit alloy-config.alloy - set central server IP
mkdir -p alloy_data
docker-compose up -d
```

---

## Verification Checklist

- [ ] Central Loki responding: `curl http://192.168.1.100:3100/ready`
- [ ] Central Grafana accessible: `http://192.168.1.100:3000`
- [ ] Remote Alloy running: `docker ps | grep alloy`
- [ ] Remote Alloy connecting: `docker logs alloy | grep -i loki`
- [ ] Grafana showing logs from all servers

---

## Troubleshooting

### Logs not appearing in Grafana

```bash
# On remote server - check Alloy
docker logs alloy

# Check network connectivity
curl http://192.168.1.100:3100/ready

# Check firewall
sudo ufw status
```

### Permission errors

```bash
# On central server
sudo chown -R 10001:10001 /opt/monitoring/loki-data
sudo chown -R 472:472 /opt/monitoring/grafana-data
```

### Connection refused

```bash
# Check if Loki is listening on all interfaces
docker exec loki netstat -tlnp | grep 3100

# Verify firewall allows port 3100
sudo ufw status | grep 3100
```

---

## Important Notes

1. **Replace IPs**: Change `192.168.1.100` to your actual central server IP in all configs
2. **Firewall**: Ensure port 3100 is open on central server
3. **Network**: All servers must be able to reach the central server IP
4. **Security**: Change default Grafana password in production
5. **Hostname**: Each remote server should have unique hostname for identification

---

## Adding New Remote Server

1. Copy Alloy setup to new server
2. Edit `alloy-config.alloy` - set correct central server IP
3. Run `docker-compose up -d`
4. Logs appear automatically in Grafana
