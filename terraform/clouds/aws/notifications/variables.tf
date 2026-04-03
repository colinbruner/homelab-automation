variable "region" {
  type    = string
  default = "us-east-1"
}

variable "domain_name" {
  type    = string
  default = "colinbruner.com"
}

variable "mail_from_subdomain" {
  type    = string
  default = "alerts"
}

variable "sns_monthly_spend_limit" {
  type        = number
  default     = 2
  description = "Monthly SMS spending limit in USD"
}
