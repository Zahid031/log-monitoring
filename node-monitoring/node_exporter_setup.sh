#!/bin/bash

# 1) Set the version you want to install
VERSION="1.10.2"

# 2) Create a node_exporter user
sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter

# 3) Download the Node Exporter binary
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/node_exporter-${VERSION}.linux-amd64.tar.gz

# 4) Extract and install
tar xvf node_exporter-${VERSION}.linux-amd64.tar.gz
sudo mv node_exporter-${VERSION}.linux-amd64/node_exporter /usr/local/bin/

# 5) Set ownership
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

# 6) Create systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# 7) Reload systemd and start service
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

echo "Node Exporter installed and started."
echo "Metrics available at http://localhost:9100/metrics"

