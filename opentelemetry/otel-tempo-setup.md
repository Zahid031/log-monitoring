# OpenTelemetry Collector + Tempo Setup Guide

This guide will help you set up a distributed tracing infrastructure using OpenTelemetry Collector and Grafana Tempo.

## Architecture Overview

This setup consists of two main components:

- **OpenTelemetry Collector**: Receives traces from your applications via OTLP protocol
- **Grafana Tempo**: Stores and queries distributed traces

The flow: `Your Applications → OTel Collector → Tempo → Query/Visualization`

## Prerequisites

- Docker and Docker Compose installed
- Root or sudo access to the server
- Basic understanding of distributed tracing concepts

## Installation Steps

### 1. Create Project Directory

```bash
sudo -i
mkdir -p ~/otel-tempo
cd ~/otel-tempo
```

### 2. Create Configuration Files

#### Create `otel-config.yaml`

This configures the OpenTelemetry Collector to receive traces and forward them to Tempo.

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: "0.0.0.0:4317"  # Bind to all interfaces
      http:
        endpoint: "0.0.0.0:4318"

exporters:
  otlp/tempo:
    endpoint: "tempo:4317"  # This connects to Tempo's OTLP receiver
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [otlp/tempo]
```

#### Create `tempo-config.yaml`

This configures Grafana Tempo for trace storage and querying.

```yaml
server:
  http_listen_port: 3200
  grpc_listen_port: 9095  # Change from 4317 to 9095
  grpc_listen_address: "0.0.0.0"

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: "0.0.0.0:4317"  # Add OTLP receiver on 4317
        http:
          endpoint: "0.0.0.0:4318"

ingester:
  trace_idle_period: 10m

storage:
  trace:
    backend: local
    local:
      path: /var/tempo/traces
```

#### Create `docker-compose.yaml`

This orchestrates both services.

```yaml
services:
  tempo:
    image: grafana/tempo:2.9.0
    container_name: tempo
    networks:
      - otel-tempo-net
    ports:
      - "3200:3200"   # only expose query port
    volumes:
      - ./tempo-data:/var/tempo/traces
      - ./tempo-config.yaml:/etc/tempo/config.yaml:ro
    command: ["-config.file=/etc/tempo/config.yaml"]
    restart: always

  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    container_name: otel-collector
    networks:
      - otel-tempo-net
    ports:
      - "4317:4317"   # OTLP gRPC to apps on other servers
      - "4318:4318"   # OTLP HTTP
    volumes:
      - ./otel-config.yaml:/etc/otel-config.yaml:ro
    command: ["--config", "/etc/otel-config.yaml"]
    depends_on:
      - tempo
    restart: always

networks:
  otel-tempo-net:
    driver: bridge
```

### 3. Create Data Directory

```bash
mkdir -p tempo-data
```

### 4. Start the Services

```bash
docker-compose up -d
```

### 5. Verify Services are Running

```bash
docker-compose ps
```

You should see both `tempo` and `otel-collector` containers running.

Check logs if needed:

```bash
docker-compose logs -f
```

## Port Configuration

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| OTel Collector | 4317 | gRPC | OTLP receiver for applications |
| OTel Collector | 4318 | HTTP | OTLP HTTP receiver |
| Tempo | 3200 | HTTP | Query API (for Grafana) |
| Tempo | 4317 | gRPC | Internal OTLP receiver (via OTel) |
| Tempo | 9095 | gRPC | Internal gRPC server |

## Connecting Your Applications

To send traces from your applications to this setup, configure your OTLP exporter to point to:

- **gRPC endpoint**: `http://<server-ip>:4317`
- **HTTP endpoint**: `http://<server-ip>:4318`

### Example: Python Application

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Configure the OTLP exporter
otlp_exporter = OTLPSpanExporter(
    endpoint="http://<server-ip>:4317",
    insecure=True
)

# Set up the tracer provider
trace.set_tracer_provider(TracerProvider())
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(otlp_exporter)
)

# Use the tracer
tracer = trace.get_tracer(__name__)
```

### Example: Node.js Application

```javascript
const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');

const provider = new NodeTracerProvider();
const exporter = new OTLPTraceExporter({
  url: 'http://<server-ip>:4317',
});

provider.addSpanProcessor(new BatchSpanProcessor(exporter));
provider.register();
```

## Querying Traces with Grafana

To visualize your traces, set up Grafana and add Tempo as a data source:

1. Install Grafana
2. Add a new data source of type "Tempo"
3. Set the URL to: `http://<tempo-server-ip>:3200`
4. Save and test the connection

## Maintenance Commands

### Stop Services
```bash
docker-compose down
```

### Restart Services
```bash
docker-compose restart
```

### View Logs
```bash
docker-compose logs -f otel-collector
docker-compose logs -f tempo
```

### Update Services
```bash
docker-compose pull
docker-compose up -d
```

### Clean Up Trace Data
```bash
sudo rm -rf tempo-data/*
```

## Troubleshooting

### Services Not Starting

Check logs for errors:
```bash
docker-compose logs
```

### No Traces Appearing

1. Verify your application is sending traces to the correct endpoint
2. Check OTel Collector logs for incoming traces
3. Check Tempo logs for ingestion errors
4. Verify network connectivity between your app and the OTel Collector

### Port Conflicts

If ports 4317, 4318, or 3200 are already in use, modify the port mappings in `docker-compose.yaml`:

```yaml
ports:
  - "14317:4317"  # Use different external port
```

## Security Considerations

This setup uses insecure connections for simplicity. For production environments:

1. Enable TLS on all connections
2. Implement authentication between services
3. Restrict network access using firewall rules
4. Use secrets management for sensitive configuration
5. Consider using a production-grade storage backend for Tempo

## Next Steps

- Set up Grafana for trace visualization
- Configure retention policies in Tempo
- Add metrics and logs collection with Prometheus and Loki
- Implement sampling strategies in the OTel Collector
- Set up alerting based on trace data

## References

- [OpenTelemetry Collector Documentation](https://opentelemetry.io/docs/collector/)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [OTLP Specification](https://opentelemetry.io/docs/specs/otlp/)

---

**Last Updated**: December 2024  
**Version**: 1.0