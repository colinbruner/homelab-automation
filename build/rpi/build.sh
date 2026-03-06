#!/usr/bin/env bash
set -euo pipefail

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
PIGEN_DIR="$SCRIPTPATH/pi-gen"

IMAGE_NAME="${1:-}"

###
# Checks
###

if [[ -z $IMAGE_NAME ]]; then
  echo "Usage: $0 <image-name> [--ip ADDRESS/PREFIX] [--gateway GW] [--dns DNS] [--interface IFACE] [--password PASS] [--ssh-key 'ssh-ed25519 ...']"
  echo ""
  echo "Available images:"
  for d in "$SCRIPTPATH/images"/*/; do
    echo "  $(basename "$d")"
  done
  exit 1
fi

shift

IMAGE_DIR="$SCRIPTPATH/images/$IMAGE_NAME"
OUTPUT_DIR="$SCRIPTPATH/bin/$IMAGE_NAME"

if [[ ! -d $IMAGE_DIR ]]; then
  echo "[ERROR]: No image directory found at $IMAGE_DIR"
  echo ""
  echo "Available images:"
  for d in "$SCRIPTPATH/images"/*/; do
    echo "  $(basename "$d")"
  done
  exit 1
fi

if [[ ! -f $IMAGE_DIR/config ]]; then
  echo "[ERROR]: Missing config file at $IMAGE_DIR/config"
  exit 1
fi

###
# Parse optional flags
###

NM_INTERFACE="eth0"
NM_ADDRESS=""
NM_GATEWAY=""
NM_DNS=""
USER_PASSWORD=""
SSH_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip)        NM_ADDRESS="$2";    shift 2 ;;
    --gateway)   NM_GATEWAY="$2";   shift 2 ;;
    --dns)       NM_DNS="$2";       shift 2 ;;
    --interface) NM_INTERFACE="$2"; shift 2 ;;
    --password)  USER_PASSWORD="$2"; shift 2 ;;
    --ssh-key)   SSH_KEY="$2";      shift 2 ;;
    *) echo "[ERROR]: Unknown flag: $1"; exit 1 ;;
  esac
done

if [[ -n $NM_ADDRESS && -z $NM_GATEWAY ]]; then
  echo "[ERROR]: --ip requires --gateway"
  exit 1
fi

if [[ -z $USER_PASSWORD && -z $SSH_KEY ]]; then
  echo "[ERROR]: Must provide --password or --ssh-key (or both)."
  echo "         Generate a hashed password: openssl passwd -6 yourpassword"
  exit 1
fi

###
# Helper: SHA-512 password hashing
# macOS ships LibreSSL which lacks -6; fall back to Docker (already required).
###

hash_password() {
  local pw="$1"
  if openssl passwd -6 "$pw" &>/dev/null 2>&1; then
    openssl passwd -6 "$pw"
  else
    echo "[INFO]: System openssl lacks -6 support (LibreSSL on macOS); using Docker to hash..." >&2
    printf '%s' "$pw" | docker run --rm -i alpine sh -c 'apk add -q --no-cache openssl >/dev/null 2>&1; read -r p; openssl passwd -6 "$p"'
  fi
}

###
# Docker checks
###

if ! command -v docker &>/dev/null; then
  echo "[ERROR]: Docker is required but not found."
  echo "         Install Docker Desktop: https://docs.docker.com/desktop/"
  exit 1
fi

if ! docker info &>/dev/null; then
  echo "[ERROR]: Docker daemon is not running. Start Docker Desktop and retry."
  exit 1
fi

###
# Clone pi-gen
###

echo "[INFO]: Cloning pi-gen (arm64 branch)..."
rm -rf "$PIGEN_DIR"
git clone --depth 1 --branch arm64 https://github.com/RPi-Distro/pi-gen.git "$PIGEN_DIR"

###
# Inject config and custom stage
###

echo "[INFO]: Copying config for '$IMAGE_NAME'..."
cp "$IMAGE_DIR/config" "$PIGEN_DIR/config"

# Inject credentials (kept out of committed config)
if [[ -n $USER_PASSWORD ]]; then
  HASHED=$(hash_password "$USER_PASSWORD")
  echo "FIRST_USER_PASS='$HASHED'" >> "$PIGEN_DIR/config"
  echo "DISABLE_FIRST_BOOT_USER_RENAME=1" >> "$PIGEN_DIR/config"
  echo "[INFO]: Password set for first user (DISABLE_FIRST_BOOT_USER_RENAME enabled)."
fi
if [[ -n $SSH_KEY ]]; then
  echo "PUBKEY_SSH_FIRST_USER=\"$SSH_KEY\"" >> "$PIGEN_DIR/config"
  echo "[INFO]: SSH public key injected for first user."
fi

if [[ -d $IMAGE_DIR/stage-custom ]]; then
  echo "[INFO]: Copying stage-custom for '$IMAGE_NAME'..."
  cp -r "$IMAGE_DIR/stage-custom" "$PIGEN_DIR/stage-custom"

  # Render 01-run-chroot.sh.tpl if it exists
  TEMPLATE="$IMAGE_DIR/stage-custom/00-config/01-run-chroot.sh.tpl"
  RENDERED="$PIGEN_DIR/stage-custom/00-config/01-run-chroot.sh"

  # Remove the template from the pi-gen copy (it's not a valid stage file)
  rm -f "$PIGEN_DIR/stage-custom/00-config/01-run-chroot.sh.tpl"

  if [[ -f $TEMPLATE ]]; then
    if [[ -n $NM_ADDRESS ]]; then
      echo "[INFO]: Rendering static IP config: $NM_ADDRESS on $NM_INTERFACE via $NM_GATEWAY"
      sed \
        -e "s|@@NM_INTERFACE@@|$NM_INTERFACE|g" \
        -e "s|@@NM_ADDRESS@@|$NM_ADDRESS|g" \
        -e "s|@@NM_GATEWAY@@|$NM_GATEWAY|g" \
        -e "s|@@NM_DNS@@|${NM_DNS:-$NM_GATEWAY}|g" \
        "$TEMPLATE" > "$RENDERED"
      chmod +x "$RENDERED"
    else
      echo "[INFO]: No --ip provided; skipping static IP (DHCP will be used)."
    fi
  fi
fi

###
# Build
###

mkdir -p "$OUTPUT_DIR"

echo "[INFO]: Building image '$IMAGE_NAME'. This typically takes 20-40 minutes."
echo "[INFO]: Logs will stream below..."

cd "$PIGEN_DIR"
./build-docker.sh

###
# Copy output
###

echo "[INFO]: Copying output image to $OUTPUT_DIR ..."
if ls "$PIGEN_DIR/deploy/"*.img.xz 1>/dev/null 2>&1; then
  cp "$PIGEN_DIR/deploy/"*.img.xz "$OUTPUT_DIR/"
elif ls "$PIGEN_DIR/deploy/"*.img 1>/dev/null 2>&1; then
  cp "$PIGEN_DIR/deploy/"*.img "$OUTPUT_DIR/"
else
  echo "[ERROR]: No image found in $PIGEN_DIR/deploy/ — check build logs above."
  exit 1
fi

echo ""
echo "[INFO]: Build complete. Output:"
ls -lh "$OUTPUT_DIR/"
echo ""
echo "[INFO]: Flash with:"
echo "        xz -d $OUTPUT_DIR/*.img.xz && sudo dd if=$OUTPUT_DIR/*.img of=/dev/sdX bs=4M status=progress conv=fsync"
echo "        OR use Raspberry Pi Imager and select the .img file."
