#!/usr/bin/env bash
#
# Creates a set of certificates for use with HashiCorp Consul
# https://learn.hashicorp.com/consul/datacenter-deploy/deployment-guide

# set -o errexit
# set -o nounset
# set -o xtrace

# https://www.shellhacks.com/yes-no-bash-script-prompt-confirmation/
read -p "Do you want to generate a new set of Consul certicates in the directory \"./tls/consul/\" [y/N]? " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

# Set working dir
CONSUL_TLS_BASE_PATH="${CONSUL_TLS_BASE_PATH:-./tls/consul/}"
mkdir -p "$CONSUL_TLS_BASE_PATH"
cd "$CONSUL_TLS_BASE_PATH"

# Cleanup previously generated certificates
rm -rf certs

# Define cert types
crt_types=("server" "cli" "client")

for type in "${crt_types[@]}"; do
  # Create certificate
  consul tls cert create -${type}
  cert="dc1-$type-consul-0.pem"
  key="dc1-$type-consul-0-key.pem"

  # Show fingerprint
  openssl x509 -in $cert -fingerprint -noout

  # Drop index
  mv $cert "dc1-${type}-consul.pem"
  mv $key "dc1-${type}-consul-key.pem"
done;

# Move to certs folder
mkdir certs
mv dc1-* certs/