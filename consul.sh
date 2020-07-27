#!/usr/bin/env bash
#
# Packer shell provisioner for HashiCorp Consul on Raspberry Pi
# https://learn.hashicorp.com/consul/datacenter-deploy/deployment-guide

# set -o errexit
# set -o nounset
set -o xtrace

CONSUL_URL="https://releases.hashicorp.com/consul"

cd "/home/${USERNAME}"

# Download Consul binary and checksums
curl -sS -O "${CONSUL_URL}/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_${CONSUL_ARCH}.zip"
curl -sS -O "${CONSUL_URL}/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_SHA256SUMS"
curl -sS -O "${CONSUL_URL}/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_SHA256SUMS.sig"

# Verify signature and zip archive
gpg --import "hashicorp.asc"
gpg --verify  "consul_${CONSUL_VERSION}_SHA256SUMS.sig" "consul_${CONSUL_VERSION}_SHA256SUMS"
shasum -a 256 -c "consul_${CONSUL_VERSION}_SHA256SUMS" --ignore-missing

# Install binary
unzip "consul_${CONSUL_VERSION}_linux_${CONSUL_ARCH}.zip"
chown root: consul
mv consul /usr/local/bin/
consul --version

# Move uploaded tls files
mkdir -p /opt/consul/tls
mv /tmp/tls/* /opt/consul/tls/

# Consul system user
useradd --system --home /etc/consul.d --shell /bin/false consul
chown --recursive consul: /opt/consul

# Change ownership and permissions for tls certs
chown consul: /opt/consul/tls/*.pem
chmod 640 /opt/consul/tls/*.pem
chmod 644 /opt/consul/tls/dc1-{cli,client}*
chmod 644 /opt/consul/tls/consul-agent-ca.pem

# Create Consul config files
mkdir -p /etc/consul.d

cat << EOF > /etc/consul.d/consul.hcl
datacenter = "dc1"
data_dir = "/opt/consul"
encrypt = "$CONSUL_ENCRYPT"

retry_join = [
  $(printf '%s\n' $CONSUL_RETRY_JOIN)
]

ports {
  server = 8300
  serf_lan = 8301
  serf_wan = -1
  http = -1
  https = 8501
  dns = 8600
}

performance {
  raft_multiplier = 1
}
EOF

cat << EOF > /etc/consul.d/server.hcl
server = true
bootstrap_expect = 3

# Auto-encrypt RPC

# "verify rpc only", because ui=true
ui = true
verify_incoming = false
verify_incoming_rpc = true
verify_outgoing = true
verify_server_hostname = true

ca_file = "/opt/consul/tls/consul-agent-ca.pem"
cert_file = "/opt/consul/tls/dc1-server-consul.pem"
key_file = "/opt/consul/tls/dc1-server-consul-key.pem"
EOF

# Configure systemd service unit
cat << EOF > /etc/systemd/system/consul.service 
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul.d/consul.hcl

[Service]
Type=notify
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
ExecReload=/usr/local/bin/consul reload
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl enable consul

# Configure .bashrc
cat << EOF >> .bashrc

complete -C /usr/local/bin/consul consul

export CONSUL_HTTP_ADDR="https://127.0.0.1:8501"
export CONSUL_CACERT="/opt/consul/tls/consul-agent-ca.pem"
export CONSUL_CLIENT_CERT="/opt/consul/tls/dc1-cli-consul.pem"
export CONSUL_CLIENT_KEY="/opt/consul/tls/dc1-cli-consul-key.pem"
EOF