# ---------------------------------------------------------------------------
# Secret Manager API
# disable_on_destroy = false so terraform destroy doesn't disable the API
# for the whole project (which may have other things using it).
# ---------------------------------------------------------------------------
resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Service Account — dedicated identity for the Pocket ID VM.
# Principle of least privilege: the only IAM bindings granted are the
# secretAccessor roles on the specific secrets this VM needs.
# ---------------------------------------------------------------------------
resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = "auth-colinbruner-com"
  display_name = "SA for auth.colinbruner.com VM"
  description  = "Runtime identity for the auth.colinbruner.com GCE instance — grants read-only access to required secrets"
}

# ---------------------------------------------------------------------------
# Secret: Cloudflare Tunnel token
# Written by Terraform from the cloudflare_zero_trust_tunnel_cloudflared
# resource; fetched at VM startup via gcloud — never embedded in the script.
# ---------------------------------------------------------------------------
resource "google_secret_manager_secret" "cloudflared_token" {
  project   = var.project_id
  secret_id = "pocket-id-cloudflared-token"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "cloudflared_token" {
  secret      = google_secret_manager_secret.cloudflared_token.id
  secret_data = cloudflare_zero_trust_tunnel_cloudflared.auth_colinbruner.tunnel_token
}

# ---------------------------------------------------------------------------
# IAM — allow the VM's SA to read the tunnel token secret (and only that secret)
# ---------------------------------------------------------------------------
resource "google_secret_manager_secret_iam_member" "auth_colinbruner_cloudflared_token" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.cloudflared_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.this.email}"
}

# ---------------------------------------------------------------------------
# Secret: backup encryption key
# A 32-byte random key stored as hex. The backup script fetches this at
# runtime and uses it as input to openssl enc (AES-256-CBC + PBKDF2).
# Rotating: create a new secret version in Secret Manager and re-encrypt any
# backups you need to restore from — old versions are not deleted automatically.
# ---------------------------------------------------------------------------
resource "random_id" "backup_key" {
  byte_length = 32
}

resource "google_secret_manager_secret" "backup_key" {
  project   = var.project_id
  secret_id = "pocket-id-backup-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "backup_key" {
  secret      = google_secret_manager_secret.backup_key.id
  secret_data = random_id.backup_key.hex
}

# ---------------------------------------------------------------------------
# IAM — allow the VM's SA to read the backup key secret
# ---------------------------------------------------------------------------
resource "google_secret_manager_secret_iam_member" "pocket_id_backup_key" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.backup_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.this.email}"
}

# ---------------------------------------------------------------------------
# Secret: Pocket ID encryption key
# A 32-byte random key stored as hex. Fetched at VM startup and written to
# /opt/pocket-id/enc_key on the persistent data disk. Because this key lives
# in Secret Manager (not on the boot disk), it survives VM replacement.
# ---------------------------------------------------------------------------
resource "random_id" "enc_key" {
  byte_length = 32
}

resource "google_secret_manager_secret" "enc_key" {
  project   = var.project_id
  secret_id = "pocket-id-enc-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "enc_key" {
  secret      = google_secret_manager_secret.enc_key.id
  secret_data = random_id.enc_key.hex
}

resource "google_secret_manager_secret_iam_member" "enc_key" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.enc_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.this.email}"
}

# ---------------------------------------------------------------------------
# IAM — allow the VM's SA to write to Cloud Logging
# Required for logging.logEntries.create (startup script + system logs).
# The cloud-platform OAuth scope on the instance is wide enough; this grants
# the SA the actual IAM permission to back it.
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.this.email}"
}
