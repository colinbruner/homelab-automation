output "fqdns" {
  description = "Record names (FQDNs) created in the zone"
  value       = module.internal_dns.fqdns
}

output "record_ids" {
  description = "Map of '<hostname>/<ip>' key to Cloudflare record ID"
  value       = module.internal_dns.record_ids
}
