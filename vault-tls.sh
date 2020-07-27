#!/usr/bin/env bash
#
# Creates a set of certificates for use with HashiCorp Vault
# https://learn.hashicorp.com/vault/operations/ops-deployment-guide

# set -o errexit
# set -o nounset
# set -o xtrace


# Read server hostnames
# VAULT_SERVER_NAMES="${1:?Error: specify server names as input param, e.g., \`./vault-tls.sh \"pi0 pi1 pi2\"\`}"

# echo $VAULT_SERVER_NAMES
# echo "${#VAULT_SERVER_NAMES[@]}"

# VAULT_SAN="${2}"

# echo "Running the script with:"
# echo "  Vault server names (CN): $VAULT_SERVER_NAMES"
# echo "  Vault service name (SAN): $VAULT_SAN"
# echo

# https://www.shellhacks.com/yes-no-bash-script-prompt-confirmation/
# read -p "Do you want to generate a new set of Vault certicates in the directory \"./tls/vault/\" [y/N]? " -n 1 -r
read -p "Do you want to generate a new Vault CA certicate in the directory \"./tls/vault/\" [y/N]? " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

# Set working dir
VAULT_TLS_BASE_PATH="${CONSUL_TLS_BASE_PATH:-./tls/vault/}"
mkdir -p "$VAULT_TLS_BASE_PATH"
cd "$VAULT_TLS_BASE_PATH"

# Cleanup previously generated certificates
rm -rf certs ca
mkdir -p certs ca

# Create CA cert
CA_CONFIG="
[ req ]
distinguished_name = dn
[ dn ]
[ ext ]
basicConstraints   = critical, CA:true, pathlen:1
keyUsage           = critical, digitalSignature, cRLSign, keyCertSign
"
openssl req -config <(echo "$CA_CONFIG") -new -newkey rsa:2048 -nodes \
  -subj "/CN=Snake Root CA" -x509 -extensions ext -keyout "./ca/vault_ca.key" -out "./ca/vault_ca.pem"