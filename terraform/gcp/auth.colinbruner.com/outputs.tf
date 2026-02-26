output "instance_name" {
  description = "GCP compute instance name"
  value       = google_compute_instance.pocket_id.name
}

output "instance_ephemeral_ip" {
  description = "Ephemeral external IP of the VM (outbound connectivity only — SSH goes through IAP, not this IP)"
  value       = google_compute_instance.pocket_id.network_interface[0].access_config[0].nat_ip
}

output "tunnel_id" {
  description = "Cloudflare Tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.pocket_id.id
}

output "pocket_id_url" {
  description = "Public URL Pocket ID is accessible at via Cloudflare Tunnel"
  value       = "https://${var.cloudflare_tunnel_hostname}"
}

output "setup_url" {
  description = "First-run setup page — visit this after apply to register your admin passkey"
  value       = "https://${var.cloudflare_tunnel_hostname}/login/setup"
}

output "ssh_command" {
  description = "SSH into the VM via IAP (no public port required)"
  value       = "gcloud compute ssh pocket-id --zone=${var.zone} --project=${var.project_id} --tunnel-through-iap"
}

output "startup_log_command" {
  description = "Tail the startup script log on the VM via IAP"
  value       = "gcloud compute ssh pocket-id --zone=${var.zone} --project=${var.project_id} --tunnel-through-iap -- 'sudo journalctl -u google-startup-scripts -f'"
}

output "backup_bucket" {
  description = "GCS bucket storing encrypted nightly SQLite backups (30-day lifecycle)"
  value       = google_storage_bucket.backups.name
}

output "backup_log_command" {
  description = "Tail the backup cron log on the VM via IAP"
  value       = "gcloud compute ssh pocket-id --zone=${var.zone} --project=${var.project_id} --tunnel-through-iap -- 'sudo tail -f /var/log/pocket-id-backup.log'"
}
