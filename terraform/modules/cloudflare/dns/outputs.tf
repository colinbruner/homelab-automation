output "record_ids" {
  description = "Map of '<hostname>/<ip>' key to the created Cloudflare record ID"
  value       = { for k, r in cloudflare_dns_record.this : k => r.id }
}

output "fqdns" {
  description = "Sorted list of record names (FQDNs) created"
  value       = sort([for r in cloudflare_dns_record.this : r.name])
}
