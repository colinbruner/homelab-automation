variable "cloudflare_api_token" {
  description = "Cloudflare API token — requires Zone:DNS:Edit permission for the zone"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for colinbruner.com"
  type        = string
}

variable "cloudflare_domain" {
  description = "Zone apex domain — used to build record FQDNs"
  type        = string
  default     = "colinbruner.com"
}
