#!/bin/bash -e

# Downloads Talos Linux vmlinuz and initramfs images from GitHub releases and
# places them under the TFTP boot path in the layout expected by the PXE role:
#
#   <TFTP_IMAGES_PATH>/talos/<version>/<arch>/vmlinuz
#   <TFTP_IMAGES_PATH>/talos/<version>/<arch>/initramfs.xz
#
# Usage:
#   ./download-talos-images.sh [version] [arch...]
#
# Examples:
#   ./download-talos-images.sh                        # uses TALOS_VERSION env or default
#   ./download-talos-images.sh v1.12.4                # explicit version, both arches
#   ./download-talos-images.sh v1.12.4 amd64          # explicit version, amd64 only
#   TFTP_IMAGES_PATH=/custom/path ./download-talos-images.sh v1.12.4
#
# Set FORCE=1 to re-download even if files already exist.

TALOS_VERSION="${1:-${TALOS_VERSION:-v1.12.4}}"
shift 2>/dev/null || true

# Remaining positional args are architectures; default to both if none given
if [[ $# -gt 0 ]]; then
    ARCHITECTURES=("$@")
else
    ARCHITECTURES=(amd64 arm64)
fi

TFTP_IMAGES_PATH="${TFTP_IMAGES_PATH:-/srv/tftp/images}"
GITHUB_BASE="https://github.com/siderolabs/talos/releases/download"
FORCE="${FORCE:-0}"
CHANGED=false

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }
err()  { echo "[ERROR] $*" >&2; }

download_file() {
    local url=$1
    local dest=$2

    if [[ -f "$dest" && "$FORCE" != "1" ]]; then
        log "Skipping $(basename "$dest") — already exists (set FORCE=1 to re-download)"
        return 0
    fi

    log "Downloading $(basename "$dest") from $url"
    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$dest" "$url"; then
        err "Failed to download $url"
        rm -f "$dest"
        return 1
    fi
    chmod 644 "$dest"
    CHANGED=true
}

for arch in "${ARCHITECTURES[@]}"; do
    dest_dir="${TFTP_IMAGES_PATH}/talos/${TALOS_VERSION}/${arch}"
    mkdir -p "$dest_dir"

    log "Fetching Talos ${TALOS_VERSION} / ${arch} → ${dest_dir}"

    download_file \
        "${GITHUB_BASE}/${TALOS_VERSION}/vmlinuz-${arch}" \
        "${dest_dir}/vmlinuz"

    download_file \
        "${GITHUB_BASE}/${TALOS_VERSION}/initramfs-${arch}.xz" \
        "${dest_dir}/initramfs.xz"
done

# Referenced by Ansible for idempotency (matches pattern used by extract-boot-disk.sh)
echo "$CHANGED"
