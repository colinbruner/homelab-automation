data "google_project" "this" {}

resource "random_id" "this" {
  byte_length = 2
}

###
# Bucket
###
resource "google_storage_bucket" "this" {
  name     = "backup-unas-vol-${var.name}-${random_id.this.hex}"
  location = "US-CENTRAL1" # Cheapest

  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true

  # https://github.com/terraform-google-modules/terraform-google-cloud-storage/blob/v11.0.0/modules/simple_bucket/main.tf#L84-L106
  dynamic "lifecycle_rule" {
    for_each = local.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lookup(lifecycle_rule.value.action, "storage_class", null)
      }
      condition {
        # NOTE: if we want this, need to define a var object with explicit types, like in module
        #send_age_if_zero           = lookup(lifecycle_rule.value.condition, "send_age_if_zero", null)
        age                        = lookup(lifecycle_rule.value.condition, "age", null)
        created_before             = lookup(lifecycle_rule.value.condition, "created_before", null)
        with_state                 = lookup(lifecycle_rule.value.condition, "with_state", contains(keys(lifecycle_rule.value.condition), "is_live") ? (lifecycle_rule.value.condition["is_live"] ? "LIVE" : null) : null)
        matches_storage_class      = lookup(lifecycle_rule.value.condition, "matches_storage_class", null) != null ? split(",", lifecycle_rule.value.condition["matches_storage_class"]) : null
        matches_prefix             = lookup(lifecycle_rule.value.condition, "matches_prefix", null) != null ? split(",", lifecycle_rule.value.condition["matches_prefix"]) : null
        matches_suffix             = lookup(lifecycle_rule.value.condition, "matches_suffix", null) != null ? split(",", lifecycle_rule.value.condition["matches_suffix"]) : null
        num_newer_versions         = lookup(lifecycle_rule.value.condition, "num_newer_versions", null)
        custom_time_before         = lookup(lifecycle_rule.value.condition, "custom_time_before", null)
        days_since_custom_time     = lookup(lifecycle_rule.value.condition, "days_since_custom_time", null)
        days_since_noncurrent_time = lookup(lifecycle_rule.value.condition, "days_since_noncurrent_time", null)
        noncurrent_time_before     = lookup(lifecycle_rule.value.condition, "noncurrent_time_before", null)
      }
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.this.id
  }

  versioning {
    enabled = true
  }
}
