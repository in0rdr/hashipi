#!/usr/bin/env bash
#
# Packer shell provisioner for HashiCorp Nomad on Raspberry Pi
# https://www.nomadproject.io/docs/install/production/deployment-guide

# set -o errexit
# set -o nounset
set -o xtrace

NOMAD_URL="https://releases.hashicorp.com/nomad"

cd "/home/${USERNAME}"

if [[ "$NOMAD_BINARY_PATH" != "./bin" ]]; then
  # Use custom binary from previous file provisioner
  mv "$NOMAD_BINARY_PATH" ./nomad
else
  # Download Nomad binary and checksums
  curl -sS -O "${NOMAD_URL}/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_${NOMAD_ARCH}.zip"
  curl -sS -O "${NOMAD_URL}/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_SHA256SUMS"
  curl -sS -O "${NOMAD_URL}/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_SHA256SUMS.sig"

  # Verify signature and zip archive
  gpg --import "hashicorp.asc"
  gpg --verify  "nomad_${NOMAD_VERSION}_SHA256SUMS.sig" "nomad_${NOMAD_VERSION}_SHA256SUMS"
  shasum -a 256 -c "nomad_${NOMAD_VERSION}_SHA256SUMS" --ignore-missing

  # Extract binary
  unzip "nomad_${NOMAD_VERSION}_linux_${NOMAD_ARCH}.zip"
fi

# Fix ownership and install binary
chown root: nomad
mv nomad /usr/local/bin/

# Check version
nomad --version

# Create Nomad data directory
mkdir -p /opt/nomad

# Create Nomads config files
mkdir -p /etc/nomad.d
chmod 700 /etc/nomad.d

cat << EOF > /etc/nomad.d/nomad.hcl
datacenter = "dc1"
data_dir = "/opt/nomad"

consul {
  address = "127.0.0.1:8501"
  ssl = true
  ca_file = "/opt/consul/tls/consul-agent-ca.pem"
  cert_file = "/opt/consul/tls/dc1-server-consul.pem"
  key_file = "/opt/consul/tls/dc1-server-consul-key.pem"
}
EOF

# this instance acts as a Nomad client agent
cat << EOF > /etc/nomad.d/client.hcl 
client {
  enabled = true
}
EOF

# ..and as a Nomad server agent
#
# https://www.nomadproject.io/docs/configuration
# Note that it is strongly recommended not to operate a node as both client and server,
# although this is supported to simplify development and testing.
cat << EOF > /etc/nomad.d/server.hcl 
server {
  enabled = true
  bootstrap_expect = 3
}
EOF

# Configure systemd service unit
cat << EOF > /etc/systemd/system/nomad.service 
[Unit]
Description=Nomad
Documentation=https://nomadproject.io/docs/
Wants=network-online.target
After=network-online.target

[Service]
ExecReload=/bin/kill -HUP 
ExecStart=/usr/local/bin/nomad agent -config /etc/nomad.d
KillMode=process
KillSignal=SIGINT
LimitNOFILE=infinity
LimitNPROC=infinity
Restart=on-failure
RestartSec=2
StartLimitBurst=3
StartLimitIntervalSec=10
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl enable nomad

# Configure .bashrc
cat << EOF >> .bashrc

complete -C /usr/local/bin/nomad nomad
EOF