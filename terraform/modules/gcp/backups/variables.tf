variable "name" {
  description = "The name of the backup"
  type        = string
}

variable "autoclass" {
  description = "To enable autoclass on bucket"
  type        = bool
  default     = false
}
