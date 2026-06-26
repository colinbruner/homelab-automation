locals {
  # Source of truth for internal A records. hostname -> [ips]
  dns = yamldecode(file("${path.module}/dns-records.yaml"))
}

module "internal_dns" {
  source = "../../../../modules/cloudflare/dns"

  zone_id   = var.cloudflare_zone_id
  zone_name = var.cloudflare_domain
  records   = local.dns.dns_records
}
