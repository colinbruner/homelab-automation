#!/usr/bin/env bash

set -euo pipefail

TARGET=$1
if [[ -z $TARGET ]]; then
  echo "[ERROR]: Missing target. Rerun: $0 <target>"
  exit 1
fi

# Read secrets from 1Password.
# NOTE: Create these items in 1Password before running.
#   - Cloudflare API token with Zone:DNS:Edit permissions for DNS-01 challenges
#   - Pocket ID OIDC client_id and client_secret (registered app in Pocket ID)
#   - A random 32+ char signing key for Caddy's JWT auth cookies
CF_TOKEN=$(op read "op://lab/cloudflare-proxmox/acme-token")
POCKET_ID_CLIENT_ID=$(op read "op://lab/test/client-id")
POCKET_ID_CLIENT_SECRET=$(op read "op://lab/test/client-secret")
CADDY_AUTH_KEY=$(op read "op://lab/caddy-lb/key")

# https://docs.ansible.com/ansible/latest/inventory_guide/intro_patterns.html#patterns-and-ansible-playbook-flags
# NOTE: must have trailing comma
ansible-playbook \
    -u pi \
    -i "${TARGET}," \
    --extra-vars "cloudflare_api_token=${CF_TOKEN} pocket_id_client_id=${POCKET_ID_CLIENT_ID} pocket_id_client_secret=${POCKET_ID_CLIENT_SECRET} caddy_auth_key=${CADDY_AUTH_KEY}" \
    rpi-lb.yml
