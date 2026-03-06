#!/usr/bin/env bash

TARGET=$1
if [[ -z $TARGET ]]; then
  echo "[ERROR]: Missing target. Rerun: $0 <target>"
  exit 1
fi

# Read the WARP Connector token from 1Password.
# NOTE: Create this item in 1Password before running.
#       The token is obtained from Cloudflare Zero Trust > Networks > WARP Connector.
WARP_TOKEN=$(op read "op://lab/cloudflare-warp-connector/token")

# https://docs.ansible.com/ansible/latest/inventory_guide/intro_patterns.html#patterns-and-ansible-playbook-flags
# NOTE: must have trailing comma
ansible-playbook \
    -u pi \
    -i "${TARGET}," \
    --extra-vars "warp_connector_token=${WARP_TOKEN}" \
    warp-connector.yml
