#!/usr/bin/env bash
set -euo pipefail

# TEMPORARY: deleted in Phase 3 when secrets move to onepassword lookups.
ANSIBLE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

# Token from Cloudflare Zero Trust > Networks > WARP Connector.
WARP_TOKEN=$(op read "op://lab/cloudflare-warp-connector/token")

cd "$ANSIBLE_DIR"
ansible-playbook \
    --extra-vars "warp_connector_token=${WARP_TOKEN}" \
    playbooks/warp-connector.yml ${@+"$@"}
