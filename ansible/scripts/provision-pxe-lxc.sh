#!/usr/bin/env bash

PROXMOX_HOST=$1

if [[ -z $PROXMOX_HOST ]]; then
  echo "Usage: $0 <proxmox-host>"
  exit 1
fi

# Read secrets from 1password, the authenticated 'op' command is assumed to be available.
ROOTPASS=$(op read "op://homelab/LXC PXE/password")
PUBKEY=$(op read "op://private/Personal Key/public key")

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# SSH as Root to Proxmox..
ansible "all" -u root -i "$PROXMOX_HOST," -m script -a "$SCRIPT_DIR/create-lxc.sh $ROOTPASS \"$PUBKEY\""
