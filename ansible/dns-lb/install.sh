#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Read secrets from 1Password.
# NOTE: Create these items in 1Password before running.
PI_PUBKEY=$(op read "op://private/Personal Key/public key")
CF_TOKEN=$(op read "op://lab/cloudflare-proxmox/acme-token")
POCKET_ID_CLIENT_ID=$(op read "op://lab/test/client-id")
POCKET_ID_CLIENT_SECRET=$(op read "op://lab/test/client-secret")
CADDY_AUTH_KEY=$(op read "op://lab/caddy-lb/key")

# Write vars to a temp file to avoid shell word-splitting on the SSH key value
TMPVARS=$(mktemp /tmp/ansible-vars-XXXXXX.yml)
trap "rm -f $TMPVARS" EXIT
printf 'pi_ssh_pubkey: "%s"\n' "$PI_PUBKEY" > "$TMPVARS"

ansible-playbook \
    -i "${SCRIPT_DIR}/inv" \
    --extra-vars "@${TMPVARS}" \
    --extra-vars "cloudflare_api_token=${CF_TOKEN} pocket_id_client_id=${POCKET_ID_CLIENT_ID} pocket_id_client_secret=${POCKET_ID_CLIENT_SECRET} caddy_auth_key=${CADDY_AUTH_KEY}" \
    dns-lb.yml ${@+"$@"}
