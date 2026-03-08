#!/usr/bin/env bash
set -euo pipefail

# Cloudflare credentials (for ACME DNS-01)
CF_TOKEN=$(op read "op://lab/cloudflare-proxmox/acme-token")
CF_ACCOUNT_ID=$(op read "op://lab/cloudflare-proxmox/account-id")
ACME_EMAIL=$(op read "op://lab/cloudflare-proxmox/acme-email")

# Pocket ID OIDC credentials
# Update the op:// paths to match your vault/item names
OIDC_ISSUER_URL=$(op read "op://lab/pocket-id-proxmox/issuer-url")
OIDC_CLIENT_ID=$(op read "op://lab/pocket-id-proxmox/client-id")
OIDC_CLIENT_SECRET=$(op read "op://lab/pocket-id-proxmox/client-secret")

ansible-playbook \
    -i inventory/hosts.yml \
    -e "cloudflare_token=${CF_TOKEN}" \
    -e "cloudflare_account_id=${CF_ACCOUNT_ID}" \
    -e "acme_contact=${ACME_EMAIL}" \
    -e "oidc_issuer_url=${OIDC_ISSUER_URL}" \
    -e "oidc_client_id=${OIDC_CLIENT_ID}" \
    -e "oidc_client_secret=${OIDC_CLIENT_SECRET}" \
    "$@" \
    configure.yml
