#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Read secrets from 1Password.
# NOTE: Create these items in 1Password before running.
PI_PUBKEY=$(op read "op://private/Personal Key/public key")
CF_TOKEN=$(op read "op://lab/cloudflare-proxmox/acme-token")
# Caddy LB
POCKET_ID_CLIENT_ID=$(op read "op://lab/caddy-lb/client-id")
POCKET_ID_CLIENT_SECRET=$(op read "op://lab/caddy-lb/client-secret")
CADDY_AUTH_KEY=$(op read "op://lab/caddy-lb/key")
# Technitium DNS admin password
TECHNITIUM_ADMIN_PASSWORD=$(op read "op://lab/technitium/password")

# Write vars to a temp file to avoid shell word-splitting on the SSH key value
TMPVARS=$(mktemp /tmp/ansible-vars-XXXXXX.yml)
trap "rm -f $TMPVARS" EXIT
printf 'pi_ssh_pubkey: "%s"\n' "$PI_PUBKEY" > "$TMPVARS"

ansible-galaxy collection install -r "${SCRIPT_DIR}/requirements/collections.yml"

ansible-playbook \
    -i "${SCRIPT_DIR}/inv" \
    --extra-vars "@${TMPVARS}" \
    --extra-vars "cloudflare_api_token=${CF_TOKEN} pocket_id_client_id=${POCKET_ID_CLIENT_ID} pocket_id_client_secret=${POCKET_ID_CLIENT_SECRET} caddy_auth_key=${CADDY_AUTH_KEY} technitium_admin_password=${TECHNITIUM_ADMIN_PASSWORD}" \
    dns-lb.yml ${@+"$@"}
