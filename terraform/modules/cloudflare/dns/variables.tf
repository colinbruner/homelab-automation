variable "zone_id" {
  description = "Cloudflare zone ID the records are created in"
  type        = string
}

variable "zone_name" {
  description = "Zone apex domain, e.g. colinbruner.com — used to build each record's FQDN (required by the v5 provider)"
  type        = string
}

variable "records" {
  description = "Map of hostname (short name, or '@' for the apex) to a list of IPv4 addresses. Each (hostname, IP) pair becomes one A record."
  type        = map(list(string))
}

variable "proxied" {
  description = "Whether records are proxied (orange cloud). Must be false for RFC1918/private IPs, which Cloudflare cannot proxy."
  type        = bool
  default     = false
}

variable "ttl" {
  description = "TTL in seconds for each record. 1 means automatic."
  type        = number
  default     = 1
}

variable "comment" {
  description = "Comment attached to each record. Has no effect on DNS responses."
  type        = string
  default     = "Managed by Terraform (homelab-automation)"
}
