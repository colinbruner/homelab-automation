terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ---------------------------------------------------------------------------
# IAP API — required for gcloud compute ssh --tunnel-through-iap
# ---------------------------------------------------------------------------
resource "google_project_service" "iap" {
  project            = var.project_id
  service            = "iap.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Firewall — allow IAP TCP forwarding to SSH
# Port 22 is only reachable from GCP's IAP proxy range (35.235.240.0/20).
# No public SSH port is exposed — access requires a valid GCP identity.
# ---------------------------------------------------------------------------
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "auth-colinbruner-com-allow-iap-ssh"
  network = "default"

  description = "Allow SSH via GCP Identity-Aware Proxy only (35.235.240.0/20)"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["allow-iap-ssh"]

  priority = 1000
}

# ---------------------------------------------------------------------------
# Persistent data disk — survives VM replacement.
#
# All Pocket ID application data lives here:
#   /opt/pocket-id/data/pocket-id.db  — SQLite database
#   /opt/pocket-id/enc_key            — encryption key (fetched from Secret Manager)
#   /opt/pocket-id/.env               — runtime config
#   /opt/pocket-id/docker-compose.yml — service definition
#   /opt/pocket-id/backup.sh          — backup script
#
# prevent_destroy ensures `terraform destroy` never deletes application data.
# Total disk: 10 GB data + 20 GB boot = 30 GB (free-tier allowance).
# ---------------------------------------------------------------------------
resource "google_compute_disk" "data" {
  project = var.project_id
  name    = "auth-colinbruner-com-data"
  type    = "pd-standard"
  zone    = var.zone
  size    = 10

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Compute instance — e2-micro (GCP free tier eligible)
#
# Free tier requirements:
#   - Machine type : e2-micro
#   - Region       : us-east1, us-west1, or us-central1
#   - Disk         : pd-standard (HDD), max 30 GB/month
#   - Network tier : STANDARD (egress cheaper; tunnel is outbound-only anyway)
#   - No static IP : ephemeral IP for SSH; Cloudflare Tunnel handles ingress
# ---------------------------------------------------------------------------
resource "google_compute_instance" "this" {
  name         = "auth-colinbruner-com"
  machine_type = "e2-micro"
  zone         = var.zone

  tags = ["auth-colinbruner-com", "allow-iap-ssh"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20            # 20 GB boot + 10 GB data disk = 30 GB free-tier allowance
      type  = "pd-standard" # HDD — free tier only covers pd-standard
    }
  }

  # Persistent data disk — mounted at /opt/pocket-id/ by the startup script.
  # device_name appears as /dev/disk/by-id/google-pocket-id-data inside the VM.
  attached_disk {
    source      = google_compute_disk.data.self_link
    device_name = "pocket-id-data"
    mode        = "READ_WRITE"
  }

  network_interface {
    network = "default"

    # Ephemeral external IP — required for outbound connectivity only
    # (cloudflared tunnel, docker image pulls, apt-get, Secret Manager calls).
    # SSH is handled entirely via IAP; this IP is never used for inbound access.
    access_config {
      network_tier = "STANDARD"
    }
  }

  metadata_startup_script = templatefile("${path.module}/scripts/startup.sh.tpl", {
    pocket_id_version       = var.pocket_id_version
    pocket_id_app_url       = var.pocket_id_app_url
    gcp_project_id          = var.project_id
    cloudflared_secret_name = google_secret_manager_secret.cloudflared_token.secret_id
    backup_bucket_name      = google_storage_bucket.backups.name
    backup_key_secret_name  = google_secret_manager_secret.backup_key.secret_id
    enc_key_secret_name     = google_secret_manager_secret.enc_key.secret_id
  })

  # Attach the dedicated SA so the VM can authenticate to Secret Manager.
  # cloud-platform scope is required for Secret Manager (no narrower scope exists);
  # actual permissions are constrained by IAM in secrets.tf, not the scope.
  service_account {
    email  = google_service_account.this.email
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true
}
