#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-192.168.1.3}"

PUBKEY=$(op read "op://private/Personal Key/public key")

# Write vars to a temp file to avoid shell word-splitting on the SSH key value
TMPVARS=$(mktemp /tmp/ansible-vars-XXXXXX.yml)
trap "rm -f $TMPVARS" EXIT
printf 'pi_ssh_pubkey: "%s"\n' "$PUBKEY" > "$TMPVARS"

ansible-playbook \
    -u root \
    -i "${TARGET}," \
    --extra-vars "@${TMPVARS}" \
    dns.yml "${@:2}"
