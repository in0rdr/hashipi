#!/usr/bin/env bash
#
# Packer shell provisioner for HashiCorp Vault on Raspberry Pi
# https://learn.hashicorp.com/vault/operations/ops-deployment-guide

# set -o errexit
# set -o nounset
set -o xtrace

VAULT_URL="https://releases.hashicorp.com/vault"

cd "/home/${USERNAME}"

# Download Vault binary and checksums
curl -sS -O "${VAULT_URL}/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${VAULT_ARCH}.zip"
curl -sS -O "${VAULT_URL}/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS"
curl -sS -O "${VAULT_URL}/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS.sig"

# Verify signature and zip archive
gpg --import "hashicorp.asc"
gpg --verify  "vault_${VAULT_VERSION}_SHA256SUMS.sig" "vault_${VAULT_VERSION}_SHA256SUMS"
shasum -a 256 -c "vault_${VAULT_VERSION}_SHA256SUMS" --ignore-missing

# Install binary
unzip "vault_${VAULT_VERSION}_linux_${VAULT_ARCH}.zip"
chown root: vault
mv vault /usr/local/bin/
vault --version

# Create Vault config directories
mkdir -p /etc/vault.d/tls
cd /etc/vault.d/tls

# Vault system user
useradd --system --home /etc/vault.d --shell /bin/false vault 

# Specify CSR parameters for server key
${VAULT_TLS_SUBJ_ALT_NAME:+", $VAULT_TLS_SUBJ_ALT_NAME"}
SERVER_CONFIG="
[ req ]
commonName         = $HOSTNAME
distinguished_name = dn
req_extensions     = ext
[ dn ]
CN                 = Common Name
[ ext ]
subjectAltName     = DNS:$HOSTNAME $VAULT_TLS_SUBJ_ALT_NAME
keyUsage=critical,digitalSignature,keyAgreement
"
# Create new private key and CSR
openssl req -config <(echo "$SERVER_CONFIG") -subj "/CN=${HOSTNAME}" -extensions ext -out "${HOSTNAME}.csr" -new -newkey rsa:2048 -nodes -keyout "${HOSTNAME}.key"
# Sign the CSR
openssl x509 -extfile <(echo "$SERVER_CONFIG") -extensions ext -req -in "${HOSTNAME}.csr" -CA "$VAULT_TLS_CA_CERT" -CAkey "$VAULT_TLS_CA_KEY" -CAcreateserial -out "${HOSTNAME}.pem" -days 365
# Show fingerprint
openssl x509 -in "${HOSTNAME}.pem" -fingerprint -noout

# Cleanup CA key
rm -rf "$VAULT_TLS_CA_KEY"

# Change permissions for tls certs
chmod 640 *.key
chmod 644 *.pem

# Concatenate CA and server certificate
cat "$VAULT_TLS_CA_CERT" >> "${HOSTNAME}.pem"

# Trust the CA
mv "$VAULT_TLS_CA_CERT" /etc/ca-certificates/trust-source/anchors/
update-ca-trust

# Allow usage of mlock syscall without root
setcap cap_ipc_lock=+ep /usr/local/bin/vault

cat << EOF > /etc/vault.d/vault.hcl
ui = true

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/vault.d/tls/$HOSTNAME.pem"
  tls_key_file  = "/etc/vault.d/tls/$HOSTNAME.key"
  tls_disable_client_certs = true
}

# HA advertisement addresses
#
# https://www.vaultproject.io/docs/configuration#high-availability-parameters
# https://www.vaultproject.io/docs/concepts/ha#client-redirection

# API_ADDR for client redirection (fallback, if request forwarding is disabled)
api_addr = "https://vault.wolke4.org:8200"
# CLUSTER_ADDR: Vault listens for server-to-server cluster requests
cluster_addr = "https://vault.wolke4.org:8201"

storage "consul" {
  address = "https://127.0.0.1:8501"
  path = "vault/"
  #token = "tbd"
  tls_ca_file = "/opt/consul/tls/consul-agent-ca.pem"
  tls_cert_file = "/opt/consul/tls/dc1-client-consul.pem"
  tls_key_file = "/opt/consul/tls/dc1-client-consul-key.pem"
}
EOF

chmod 640 /etc/vault.d/vault.hcl

# Configure systemd service unit
cat << EOF > /etc/systemd/system/vault.service 
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=60
StartLimitIntervalSec=60
StartLimitBurst=3
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl enable vault

# Configure .bashrc
cat << EOF >> "/home/${USERNAME}/.bashrc"

complete -C /usr/local/bin/vault vault
export VAULT_ADDR="https://$HOSTNAME:8200"
EOF

# Change ownership for config directory 
chown -R vault: /etc/vault.d/

echo 0