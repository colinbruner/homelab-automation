#!/usr/bin/env bash
set -euo pipefail

# TEMPORARY: deleted in Phase 3 when secrets move to onepassword lookups.
ANSIBLE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

CF_TOKEN=$(op read "op://lab/cloudflare-proxmox/acme-token")
POCKET_ID_CLIENT_ID=$(op read "op://lab/caddy-lb/client-id")
POCKET_ID_CLIENT_SECRET=$(op read "op://lab/caddy-lb/client-secret")
CADDY_AUTH_KEY=$(op read "op://lab/caddy-lb/key")
TECHNITIUM_ADMIN_PASSWORD=$(op read "op://lab/technitium/password")

cd "$ANSIBLE_DIR"
ansible-galaxy collection install -r requirements.yml

ansible-playbook \
    --extra-vars "cloudflare_api_token=${CF_TOKEN} caddy_lb_oidc_client_id=${POCKET_ID_CLIENT_ID} caddy_lb_oidc_client_secret=${POCKET_ID_CLIENT_SECRET} caddy_lb_auth_key=${CADDY_AUTH_KEY} technitium_admin_password=${TECHNITIUM_ADMIN_PASSWORD}" \
    playbooks/dns-lb.yml ${@+"$@"}
