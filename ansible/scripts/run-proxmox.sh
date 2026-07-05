#!/usr/bin/env bash
set -euo pipefail

# TEMPORARY: deleted in Phase 3 when secrets move to onepassword lookups.
ANSIBLE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

# Cloudflare credentials (for ACME DNS-01)
CF_TOKEN=$(op read "op://lab/cloudflare-proxmox/acme-token")
CF_ACCOUNT_ID=$(op read "op://lab/cloudflare-proxmox/account-id")
ACME_EMAIL=$(op read "op://lab/cloudflare-proxmox/acme-email")

# Pocket ID OIDC credentials
OIDC_ISSUER_URL=$(op read "op://lab/pocket-id-proxmox/issuer-url")
OIDC_CLIENT_ID=$(op read "op://lab/pocket-id-proxmox/client-id")
OIDC_CLIENT_SECRET=$(op read "op://lab/pocket-id-proxmox/client-secret")

cd "$ANSIBLE_DIR"
ansible-playbook \
    -e "proxmox_cloudflare_token=${CF_TOKEN}" \
    -e "proxmox_cloudflare_account_id=${CF_ACCOUNT_ID}" \
    -e "proxmox_acme_contact=${ACME_EMAIL}" \
    -e "proxmox_oidc_issuer_url=${OIDC_ISSUER_URL}" \
    -e "proxmox_oidc_client_id=${OIDC_CLIENT_ID}" \
    -e "proxmox_oidc_client_secret=${OIDC_CLIENT_SECRET}" \
    "$@" \
    playbooks/proxmox.yml
