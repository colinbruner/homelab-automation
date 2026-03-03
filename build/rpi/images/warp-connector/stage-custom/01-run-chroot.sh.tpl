#!/bin/bash -e

# Static IP configuration via NetworkManager keyfile.
# Raspberry Pi OS (Bookworm+) uses NetworkManager by default.
#
# Values are rendered at build time by build.sh — do not edit @@VAR@@ placeholders.

INTERFACE="@@NM_INTERFACE@@"
ADDRESS="@@NM_ADDRESS@@"
GATEWAY="@@NM_GATEWAY@@"
DNS="@@NM_DNS@@"

NM_CONN_DIR="/etc/NetworkManager/system-connections"
NM_CONN_FILE="${NM_CONN_DIR}/static-${INTERFACE}.nmconnection"

mkdir -p "$NM_CONN_DIR"

cat > "$NM_CONN_FILE" <<EOF
[connection]
id=static-${INTERFACE}
type=ethernet
interface-name=${INTERFACE}
autoconnect=true

[ethernet]

[ipv4]
method=manual
addresses=${ADDRESS}
gateway=${GATEWAY}
dns=${DNS}

[ipv6]
method=auto
EOF

# NetworkManager requires connection files to be owner-readable only
chmod 600 "$NM_CONN_FILE"
