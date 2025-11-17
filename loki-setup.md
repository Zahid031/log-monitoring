# Loki Server Setup

## Files

### docker-compose.yml

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
```

### loki-config.yaml

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

## Setup Instructions

1. Create data directory:
   ```bash
   mkdir -p loki-data && sudo chown -R 10001:10001 loki-data/
   ```

2. Start Loki:
   ```bash
   docker-compose up -d
   ```

3. Verify:
   ```bash
   curl http://localhost:3100/ready
   ```

## Notes

- Loki runs on port 3100
- Logs retained for 7 days (168h)
- Data stored in `./loki-data/`