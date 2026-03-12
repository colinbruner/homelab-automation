#!/bin/bash -e

###############################################################################
# Install Docker
# The convenience script detects the OS and installs the correct packages.
# The daemon won't start here (pi-gen chroot blocks service starts) — it will
# start automatically on first boot.
###############################################################################
curl -fsSL https://get.docker.com | sh

###############################################################################
# Install Caddy (base package via official apt repo)
#
# The base package is baked in so the service and systemd unit are present.
# Ansible replaces the binary post-boot with a custom plugin build:
#   - caddy-dns/cloudflare  (DNS-01 TLS challenge)
#   - greenpau/caddy-security  (OIDC auth portal)
###############################################################################
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | tee /etc/apt/sources.list.d/caddy-stable.list

apt-get update -y
apt-get install -y caddy

###############################################################################
# Technitium DNS Server is intentionally NOT installed here.
#
# The Technitium installer requires a running systemd (PID 1), which is not
# present in a pi-gen chroot. Installation is handled post-boot by Ansible:
#   ansible/dns-lb/roles/dns/tasks/install.yml
###############################################################################
