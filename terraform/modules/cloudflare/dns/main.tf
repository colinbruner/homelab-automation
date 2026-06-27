locals {
  # Flatten the hostname -> [ips] map into individual records, keyed by
  # "<hostname>/<ip>" so for_each keys are stable when IPs are added/removed.
  flattened_records = merge([
    for hostname, ips in var.records : {
      for ip in ips : "${hostname}/${ip}" => {
        hostname = hostname
        ip       = ip
      }
    }
  ]...)
}

resource "cloudflare_dns_record" "this" {
  for_each = local.flattened_records

  zone_id = var.zone_id
  name    = each.value.hostname == "@" ? var.zone_name : "${each.value.hostname}.${var.zone_name}"
  type    = "A"
  content = each.value.ip
  ttl     = var.ttl
  proxied = var.proxied
  comment = var.comment
}
