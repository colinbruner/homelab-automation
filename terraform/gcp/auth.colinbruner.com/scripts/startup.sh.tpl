#!/bin/bash
# Pocket ID startup script — rendered by Terraform templatefile() before upload.
#
# Secrets are NOT embedded here. They are fetched at runtime from GCP Secret
# Manager using the VM's attached Service Account credentials.
set -euo pipefail

# Non-sensitive config — resolved by Terraform at plan time
POCKET_ID_VERSION="${pocket_id_version}"
POCKET_ID_APP_URL="${pocket_id_app_url}"
GCP_PROJECT_ID="${gcp_project_id}"
CLOUDFLARED_SECRET_NAME="${cloudflared_secret_name}"
BACKUP_BUCKET="${backup_bucket_name}"
BACKUP_KEY_SECRET_NAME="${backup_key_secret_name}"
ENC_KEY_SECRET_NAME="${enc_key_secret_name}"

POCKET_ID_DIR="/opt/pocket-id"

# Prevent apt/dpkg from trying to open interactive prompts during package
# installation. Without this, dpkg-preconfigure fails with
# "unable to re-open stdin" in the startup script's non-interactive context.
export DEBIAN_FRONTEND=noninteractive

log() {
  echo "[startup] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a /var/log/pocket-id-startup.log
}

step() {
  echo "" | tee -a /var/log/pocket-id-startup.log
  echo "[startup] $(date '+%Y-%m-%d %H:%M:%S') ===== $* =====" | tee -a /var/log/pocket-id-startup.log
}

log "=== Pocket ID startup script begin ==="

# ---------------------------------------------------------------------------
# 1. System update
# ---------------------------------------------------------------------------
step "1/12: System update"
apt-get update -y
apt-get upgrade -y
log "1/12 done"

# ---------------------------------------------------------------------------
# 2. Swap — e2-micro has 1 GB RAM; swap prevents OOM on container pulls
# ---------------------------------------------------------------------------
step "2/12: Swap"
if [ ! -f /swapfile ]; then
  fallocate -l 512M /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  log "512 MB swapfile created"
else
  log "swapfile already exists, skipping"
fi
log "2/12 done"

# ---------------------------------------------------------------------------
# 3. Mount persistent data disk
#    Device appears as /dev/disk/by-id/google-pocket-id-data (set by
#    device_name in the Terraform attached_disk block).
#    - First boot: no filesystem signature → format ext4.
#    - Subsequent boots: blkid finds existing filesystem → skip format.
#    - nofail in fstab: VM still boots if disk is temporarily detached.
# ---------------------------------------------------------------------------
step "3/12: Mount data disk"
DEVICE="/dev/disk/by-id/google-pocket-id-data"

if ! blkid "$DEVICE" &>/dev/null; then
  log "New disk detected — formatting ext4..."
  mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard "$DEVICE"
fi

mkdir -p "$POCKET_ID_DIR"
if ! mountpoint -q "$POCKET_ID_DIR"; then
  mount -o discard,defaults "$DEVICE" "$POCKET_ID_DIR"
fi

if ! grep -q "$DEVICE" /etc/fstab; then
  echo "$DEVICE $POCKET_ID_DIR ext4 discard,defaults,nofail 0 2" >> /etc/fstab
fi
log "3/12 done — data disk mounted at $POCKET_ID_DIR"

# ---------------------------------------------------------------------------
# 4. Install Docker CE (official Debian repo)
# ---------------------------------------------------------------------------
step "4/12: Install Docker CE"
apt-get install -y ca-certificates curl gnupg sqlite3

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
log "Docker installed: $(docker --version)"
log "4/12 done"

# ---------------------------------------------------------------------------
# 5. Fetch encryption key from Secret Manager (idempotent)
#    enc_key lives on the persistent data disk — survives VM replacement.
#    It is never generated locally; Terraform manages the value in Secret Manager.
# ---------------------------------------------------------------------------
step "5/12: Pocket ID data directory + encryption key"
mkdir -p "$POCKET_ID_DIR/data"

if [ ! -f "$POCKET_ID_DIR/enc_key" ]; then
  log "Fetching encryption key from Secret Manager..."
  gcloud secrets versions access latest \
    --secret="$ENC_KEY_SECRET_NAME" \
    --project="$GCP_PROJECT_ID" \
    --quiet > "$POCKET_ID_DIR/enc_key"
  chmod 600 "$POCKET_ID_DIR/enc_key"
else
  log "enc_key present on data disk, skipping"
fi

chown -R 1000:1000 "$POCKET_ID_DIR"
log "5/12 done"

# ---------------------------------------------------------------------------
# 6. Write .env
# ---------------------------------------------------------------------------
step "6/12: Write .env"
cat > "$POCKET_ID_DIR/.env" <<EOF
APP_URL=$POCKET_ID_APP_URL
TRUST_PROXY=true
ENCRYPTION_KEY_FILE=/app/enc_key
PUID=1000
PGID=1000
EOF
log "6/12 done"

# ---------------------------------------------------------------------------
# 7. Write docker-compose.yml
#    - network_mode: host so cloudflared can reach localhost:1411
#    - enc_key mounted read-only
#    - Watchtower for automatic daily image updates
# ---------------------------------------------------------------------------
step "7/12: Write docker-compose.yml"
cat > "$POCKET_ID_DIR/docker-compose.yml" <<EOF
services:
  pocket-id:
    image: ghcr.io/pocket-id/pocket-id:$POCKET_ID_VERSION
    container_name: pocket-id
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./data:/app/data
      - ./enc_key:/app/enc_key:ro
    healthcheck:
      test: ["CMD", "/app/pocket-id", "healthcheck"]
      interval: 90s
      timeout: 5s
      retries: 2
      start_period: 15s
    # host networking: cloudflared connects to localhost:1411 directly
    network_mode: host

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    # Check for updates once per day; clean up old images after pulling
    command: --interval 86400 --cleanup pocket-id
EOF
log "7/12 done"

# ---------------------------------------------------------------------------
# 8. Pull images and start Pocket ID
# ---------------------------------------------------------------------------
step "8/12: Pull images and start Pocket ID"
docker compose -f "$POCKET_ID_DIR/docker-compose.yml" pull
docker compose -f "$POCKET_ID_DIR/docker-compose.yml" up -d
log "Pocket ID containers started"
log "8/12 done"

# ---------------------------------------------------------------------------
# 9. Fetch secrets from GCP Secret Manager
#    The VM's Service Account has secretAccessor on these secrets only.
#    gcloud is pre-installed on Debian GCE images and uses ADC automatically
#    via the metadata server — no explicit authentication needed.
# ---------------------------------------------------------------------------
step "9/12: Fetch secrets from Secret Manager"
log "Project: $GCP_PROJECT_ID | Cloudflared secret: $CLOUDFLARED_SECRET_NAME | Enc key secret: $ENC_KEY_SECRET_NAME"

CLOUDFLARED_TOKEN=$(gcloud secrets versions access latest \
  --secret="$CLOUDFLARED_SECRET_NAME" \
  --project="$GCP_PROJECT_ID" \
  --quiet)

log "Cloudflared token fetched"
log "9/12 done"

# ---------------------------------------------------------------------------
# 10. Install cloudflared and register as systemd service
#    cloudflared connects outbound to Cloudflare — no inbound firewall rules needed.
# ---------------------------------------------------------------------------
step "10/12: Install and start cloudflared"
curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb" \
  -o /tmp/cloudflared.deb
dpkg -i /tmp/cloudflared.deb
rm /tmp/cloudflared.deb
log "cloudflared package installed"

cloudflared service install "$CLOUDFLARED_TOKEN"
unset CLOUDFLARED_TOKEN  # clear from env after use
systemctl enable --now cloudflared
log "cloudflared service started"
log "10/12 done"

# ---------------------------------------------------------------------------
# 11. Write backup script
#
# Two-part heredoc pattern:
#   Part 1 (unquoted EOF)     — bash expands $VARS from this startup script,
#                               baking GCP_PROJECT_ID / BACKUP_BUCKET /
#                               BACKUP_KEY_SECRET_NAME into the file at VM boot.
#   Part 2 (single-quoted EOF) — bash does NOT expand anything, so variables
#                               like $DATE and $BACKUP_KEY remain as literals
#                               to be expanded when the cron job actually runs.
# ---------------------------------------------------------------------------
step "11/12: Write backup script"

# Part 1: embed non-sensitive runtime values
cat > /opt/pocket-id/backup.sh <<EOF
#!/bin/bash
set -euo pipefail

GCP_PROJECT_ID="$GCP_PROJECT_ID"
BACKUP_BUCKET="$BACKUP_BUCKET"
BACKUP_KEY_SECRET_NAME="$BACKUP_KEY_SECRET_NAME"
POCKET_ID_DIR="/opt/pocket-id"
EOF

# Part 2: static script body — variables preserved as literals for cron execution
cat >> /opt/pocket-id/backup.sh <<'BACKUP_EOF'
DB_PATH="$POCKET_ID_DIR/data/pocket-id.db"
BACKUP_TMP="/tmp/pocket-id.db"
ENCRYPTED_TMP="/tmp/pocket-id.db.enc"
# Fixed destination — each upload creates a new GCS version of the same object.
# GCS versioning + the num_newer_versions lifecycle rule keep the last 7 versions.
DEST="gs://$BACKUP_BUCKET/pocket-id.db.enc"

log() { echo "[backup] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

cleanup() {
  unset BACKUP_KEY
  rm -f "$BACKUP_TMP" "$ENCRYPTED_TMP"
}
trap cleanup EXIT

log "=== Pocket ID backup starting ==="

if [ ! -f "$DB_PATH" ]; then
  log "Database not found at $DB_PATH — skipping"
  exit 0
fi

# Fetch encryption key at runtime — never stored on disk
log "Fetching backup encryption key from Secret Manager..."
BACKUP_KEY=$(gcloud secrets versions access latest \
  --secret="$BACKUP_KEY_SECRET_NAME" \
  --project="$GCP_PROJECT_ID" \
  --quiet)

# Safe online backup using SQLite's backup API (safe during concurrent writes)
log "Creating SQLite backup..."
sqlite3 "$DB_PATH" ".backup '$BACKUP_TMP'"

# Encrypt: AES-256-CBC with PBKDF2 key derivation (600k iterations)
# To decrypt: echo "<key>" | openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass stdin -in <file>
log "Encrypting backup..."
echo "$BACKUP_KEY" | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -pass stdin \
  -in "$BACKUP_TMP" -out "$ENCRYPTED_TMP"

# Upload to GCS
log "Uploading to $DEST..."
gcloud storage cp "$ENCRYPTED_TMP" "$DEST" \
  --project="$GCP_PROJECT_ID" \
  --quiet

log "=== Backup complete: $DEST ($(date '+%Y-%m-%d')) ==="
BACKUP_EOF

chmod 750 /opt/pocket-id/backup.sh
log "11/12 done"

# ---------------------------------------------------------------------------
# 12. Install nightly cron job (02:00 UTC)
# ---------------------------------------------------------------------------
step "12/12: Install backup cron job"
echo "0 2 * * * root /opt/pocket-id/backup.sh >> /var/log/pocket-id-backup.log 2>&1" \
  > /etc/cron.d/pocket-id-backup
chmod 644 /etc/cron.d/pocket-id-backup
log "12/12 done"

log "=== Startup complete ==="
log "Pocket ID will be reachable at $POCKET_ID_APP_URL once the tunnel is established."
log "First-run setup: $POCKET_ID_APP_URL/login/setup"
