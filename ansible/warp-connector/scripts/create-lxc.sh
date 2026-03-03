#!/usr/bin/env bash

# NOTE: This script is intended to be run on the Proxmox host, as root.
#       Ansible is intended to act as the task runner for this.
# There are some hardcoded attributes here worth noting:
# - The LXC container ID is hardcoded to 1002
# - The LXC container hostname is hardcoded to "warp-connector"
# - The LXC container IP address is hardcoded to 192.168.10.2/24
ROOTPASS=$1
PUBKEY=$2
PUBKEY_FILE="/root/pct-1002.pub"

if [[ -z $ROOTPASS || -z $PUBKEY ]]; then
  echo "Usage: $0 <root-password> <public-key>"
  exit 1
fi

cleanup() {
  rm -f $PUBKEY_FILE
}
trap cleanup EXIT

ct_status() {
  # $ pct list
  # VMID       Status     Lock         Name
  # 1002       running                 warp-connector
  pct list | awk 'NR>1 && $1==1002 {print $2}'
}

STATUS=$(ct_status)

if [[ $STATUS == "running" ]]; then
  echo "[INFO]: warp-connector is already running, nothing to do."
  exit 0
elif [[ -n $STATUS ]]; then
  echo "[INFO]: CT 1002 exists (status: $STATUS), starting."
  pct start 1002
  exit 0
fi

TEMPLATE="debian-12-standard_12.12-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/${TEMPLATE}"

if [[ ! -f $TEMPLATE_PATH ]]; then
  echo "[INFO]: Template not found, downloading ${TEMPLATE}..."
  pveam update
  pveam download local $TEMPLATE
fi

echo "$PUBKEY" > $PUBKEY_FILE

pct create 1002 \
  "$TEMPLATE_PATH" \
  --hostname warp-connector \
  --memory 512 \
  --cores 1 \
  --net0 name=eth0,bridge=vmbr0,firewall=1,gw=192.168.10.1,ip=192.168.10.2/24,type=veth \
  --storage local-lvm \
  --rootfs local-lvm:8 \
  --unprivileged 0 \
  --ssh-public-keys "$PUBKEY_FILE" \
  --ostype debian \
  --password="$ROOTPASS" \
  --start 1
